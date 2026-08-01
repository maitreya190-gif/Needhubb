import { Router, type IRouter } from 'express'
import multer from 'multer'
import { prisma } from '../../lib/prisma'
import { authenticate, type AuthedRequest } from '../../middleware/authenticate'
import { badRequest, forbidden, notFound } from '../../lib/http-error'
import { uploadFile, storageKey } from '../../lib/storage'
import { isBlockedBetween, areFriends } from '../friends/friends.service'
import { pushNotification } from '../../lib/notifications'
import { emitToThread, emitToUser } from '../../lib/socket'

export const messagingRouter: IRouter = Router()

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (!file.mimetype.startsWith('image/')) cb(new Error('Images only'))
    else cb(null, true)
  },
})

/** Canonical DmThread key: smaller id first. */
function sortedPair(a: string, b: string): [string, string] {
  return a < b ? [a, b] : [b, a]
}

// ── GET /chats ────────────────────────────────────────────────────────────────

messagingRouter.get('/', authenticate, async (req, res, next) => {
  try {
    const userId = (req as AuthedRequest).userId!

    const threads = await prisma.dmThread.findMany({
      where: { OR: [{ userAId: userId }, { userBId: userId }] },
      include: {
        messages: {
          orderBy: { createdAt: 'desc' },
          take: 1,
          include: { sender: { select: { id: true, displayName: true } } },
        },
      },
      orderBy: { createdAt: 'desc' },
    })

    const result = (
      await Promise.all(
        threads.map(async (t) => {
          const otherId = t.userAId === userId ? t.userBId : t.userAId
          const other = await prisma.user.findUnique({
            where: { id: otherId },
            select: {
              id: true,
              displayName: true,
              username: true,
              profile: {
                select: {
                  avatarUrl: true,
                  bio: true,
                  personalityNickname: true,
                  personalitySummary: true,
                  personalityVibeTags: true,
                  personalityTraits: true,
                },
              },
            },
          })
          if (!other || !other.displayName) return null

          const unread = await prisma.dmMessage.count({
            where: { threadId: t.id, senderId: { not: userId }, readAt: null },
          })
          return {
            threadId: t.id,
            kind: 'dm',
            otherUser: other,
            lastMessage: t.messages[0] ?? null,
            unreadCount: unread,
            updatedAt: t.messages[0]?.createdAt ?? t.createdAt,
          }
        }),
      )
    ).filter((x): x is NonNullable<typeof x> => x !== null)

    res.json(result.sort((a, b) => new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime()))
  } catch (err) { next(err) }
})

// ── GET /chats/:threadId/messages ─────────────────────────────────────────────

messagingRouter.get('/:threadId/messages', authenticate, async (req, res, next) => {
  try {
    const userId = (req as AuthedRequest).userId!
    const { threadId } = req.params
    const since = req.query.since as string | undefined
    const before = req.query.before as string | undefined
    const limit = Math.min(Number(req.query.limit) || 50, 100)

    const thread = await prisma.dmThread.findUnique({ where: { id: threadId } })
    if (!thread) return next(notFound('Thread not found', 'THREAD_NOT_FOUND'))
    if (thread.userAId !== userId && thread.userBId !== userId) {
      return next(forbidden('Not a participant', 'FORBIDDEN'))
    }

    let cursorWhere = {}
    if (since) {
      const pivot = await prisma.dmMessage.findUnique({ where: { id: since }, select: { createdAt: true } })
      if (pivot) cursorWhere = { createdAt: { gt: pivot.createdAt } }
    } else if (before) {
      const pivot = await prisma.dmMessage.findUnique({ where: { id: before }, select: { createdAt: true } })
      if (pivot) cursorWhere = { createdAt: { lt: pivot.createdAt } }
    }

    const messages = await prisma.dmMessage.findMany({
      where: { threadId, ...cursorWhere },
      orderBy: { createdAt: since ? 'asc' : 'desc' },
      take: limit,
      include: {
        sender: { select: { id: true, displayName: true, profile: { select: { avatarUrl: true } } } },
        replyTo: { select: { id: true, body: true, imageUrl: true, senderId: true, createdAt: true, sender: { select: { id: true, displayName: true } } } }
      },
    })
    
    if (messages.length > 0) {
      console.log('DEBUG reactions type:', typeof messages[0].reactions, messages[0].reactions);
    }

    // Mark fetched messages as read + notify the sender in real time so
    // their double-tick turns blue.
    const nowReadIds = (await prisma.dmMessage.findMany({
      where: { threadId, senderId: { not: userId }, readAt: null },
      select: { id: true, senderId: true },
    }))
    if (nowReadIds.length > 0) {
      await prisma.dmMessage.updateMany({
        where: { id: { in: nowReadIds.map(m => m.id) } },
        data: { readAt: new Date() },
      })
      // Group ids by sender and emit to the thread room so any open
      // conversation UI can update instantly.
      emitToThread(threadId, 'messages_read', {
        threadId,
        messageIds: nowReadIds.map(m => m.id),
        readerId: userId,
      })
    }

    // Also mark the coalesced chat notification as read so next message
    // from this sender starts a fresh notification.
    const otherUserId = thread.userAId === userId ? thread.userBId : thread.userAId
    await prisma.notification.updateMany({
      where: {
        userId,
        type: 'MESSAGE_RECEIVED',
        refType: 'USER',
        refId: otherUserId,
        readAt: null,
      },
      data: { readAt: new Date() },
    })

    res.json(since ? messages : messages.reverse())
  } catch (err) { next(err) }
})

// ── POST /chats/:threadId/mark-read ───────────────────────────────────────────
// Lightweight: mark the other party's messages as read + emit so their tick
// turns blue instantly. Called when the recipient receives a socket event
// while the conversation is open.
messagingRouter.post('/:threadId/mark-read', authenticate, async (req, res, next) => {
  try {
    const userId = (req as AuthedRequest).userId!
    const threadId = req.params.threadId
    const thread = await prisma.dmThread.findUnique({ where: { id: threadId } })
    if (!thread) return next(notFound('Thread not found', 'NOT_FOUND'))
    if (thread.userAId !== userId && thread.userBId !== userId) {
      return next(forbidden('Not your thread', 'FORBIDDEN'))
    }
    const nowRead = await prisma.dmMessage.findMany({
      where: { threadId, senderId: { not: userId }, readAt: null },
      select: { id: true },
    })
    if (nowRead.length > 0) {
      const ids = nowRead.map(m => m.id)
      await prisma.dmMessage.updateMany({
        where: { id: { in: ids } },
        data: { readAt: new Date() },
      })
      emitToThread(threadId, 'messages_read', {
        threadId, messageIds: ids, readerId: userId,
      })
    }
    res.json({ ok: true, count: nowRead.length })
  } catch (err) { next(err) }
})

// ── POST /chats/dm/:userId/messages ───────────────────────────────────────────

messagingRouter.post('/dm/:userId/messages', authenticate, upload.single('image'), async (req, res, next) => {
  try {
    const senderId = (req as AuthedRequest).userId!
    const { userId: recipientId } = req.params
    const body = (req.body.body as string | undefined)?.trim() ?? ''
    const replyToId = req.body.replyToId as string | undefined

    if (!body && !req.file) return next(badRequest('Message body or image required', 'EMPTY_MESSAGE'))
    if (recipientId === senderId) return next(badRequest('Cannot DM yourself', 'SELF_DM'))

    const recipient = await prisma.user.findUnique({ where: { id: recipientId }, select: { id: true } })
    if (!recipient) return next(notFound('User not found', 'USER_NOT_FOUND'))

    if (await isBlockedBetween(senderId, recipientId)) {
      return next(forbidden('Cannot message this user', 'BLOCKED'))
    }

    const friends = await areFriends(senderId, recipientId)
    if (!friends) {
      // Allow messaging without friendship in two other cases:
      //   1. Both users are in active chitchat mode
      //   2. An accepted InterestResponse exists between the two users
      //      (poster accepted the responder's offer, or vice versa) —
      //      this is the "you can chat once accepted" flow.
      const now = new Date()
      const [myProfile, theirProfile, acceptedResp] = await Promise.all([
        prisma.profile.findUnique({ where: { userId: senderId }, select: { chitchatAvailableUntil: true } }),
        prisma.profile.findUnique({ where: { userId: recipientId }, select: { chitchatAvailableUntil: true } }),
        prisma.interestResponse.findFirst({
          where: {
            status: 'ACCEPTED',
            OR: [
              { responderId: senderId, need: { posterId: recipientId } },
              { responderId: recipientId, need: { posterId: senderId } },
            ],
          },
          select: { id: true },
        }),
      ])
      const chitchatActive = myProfile?.chitchatAvailableUntil && myProfile.chitchatAvailableUntil > now
        && theirProfile?.chitchatAvailableUntil && theirProfile.chitchatAvailableUntil > now
      if (!chitchatActive && !acceptedResp) {
        return next(forbidden('Must be friends, both in chitchat mode, or have an accepted offer to send messages', 'NOT_FRIENDS'))
      }
    }

    let imageUrl: string | null = null
    if (req.file) {
      const key = storageKey(`dm/${[senderId, recipientId].sort().join('-')}`, req.file.originalname)
      imageUrl = await uploadFile(key, req.file.buffer, req.file.mimetype)
    }

    const [userAId, userBId] = sortedPair(senderId, recipientId)

    const sender = await prisma.user.findUnique({
      where: { id: senderId },
      select: { displayName: true },
    })

    const message = await prisma.$transaction(async (tx) => {
      const thread = await tx.dmThread.upsert({
        where: { userAId_userBId: { userAId, userBId } },
        create: { userAId, userBId },
        update: {},
      })
      const msg = await tx.dmMessage.create({
        data: { threadId: thread.id, senderId, body: body || '', imageUrl, replyToId, reactions: {} },
        include: {
          sender: { select: { id: true, displayName: true, profile: { select: { avatarUrl: true } } } },
          thread: { select: { id: true } },
          replyTo: { select: { id: true, body: true, imageUrl: true, senderId: true, createdAt: true, sender: { select: { id: true, displayName: true } } } }
        },
      })
      const preview = body ? body.slice(0, 60) : '📷 Image'
      await pushNotification(tx, {
        userId: recipientId,
        type: 'MESSAGE_RECEIVED',
        title: sender?.displayName ?? 'New message',
        body: preview,
        refType: 'USER',
        refId: senderId,
      })
      return msg
    })

    // Real-time: push to thread room + recipient's personal room
    emitToThread(message.thread.id, 'new_message', message)
    emitToUser(recipientId, 'new_message', message)
    emitToUser(recipientId, 'new_notification', { type: 'MESSAGE_RECEIVED' })

    res.status(201).json(message)
  } catch (err) { next(err) }
})

// ── DELETE /chats/messages/:id ────────────────────────────────────────────────

messagingRouter.delete('/messages/:id', authenticate, async (req, res, next) => {
  try {
    const userId = (req as AuthedRequest).userId!
    const msg = await prisma.dmMessage.findUnique({ where: { id: req.params.id } })
    if (!msg) return next(notFound('Message not found', 'NOT_FOUND'))
    if (msg.senderId !== userId) return next(forbidden('Not your message', 'FORBIDDEN'))
    await prisma.dmMessage.delete({ where: { id: req.params.id } })
    emitToThread(msg.threadId, 'message_deleted', { messageId: req.params.id })
    res.json({ ok: true })
  } catch (err) { next(err) }
})

// ── POST /chats/messages/:id/react ────────────────────────────────────────────

messagingRouter.post('/messages/:id/react', authenticate, async (req, res, next) => {
  try {
    const userId = (req as AuthedRequest).userId!
    const msgId = req.params.id
    const emoji = (req.body.emoji as string | undefined)?.trim()

    if (!emoji) return next(badRequest('Emoji is required', 'NO_EMOJI'))

    const msg = await prisma.dmMessage.findUnique({ where: { id: msgId } })
    if (!msg) return next(notFound('Message not found', 'NOT_FOUND'))

    const thread = await prisma.dmThread.findUnique({ where: { id: msg.threadId } })
    if (!thread || (thread.userAId !== userId && thread.userBId !== userId)) {
      return next(forbidden('Not allowed to react to this message', 'FORBIDDEN'))
    }

    const currentReactions: Record<string, string> = {
      ...((msg.reactions as Record<string, string> | null) || {}),
    }
    
    if (currentReactions[userId] === emoji) {
      delete currentReactions[userId]
    } else {
      currentReactions[userId] = emoji
    }

    const updated = await prisma.dmMessage.update({
      where: { id: msgId },
      data: { reactions: currentReactions },
    })

    const recipientId = msg.senderId === userId ? (thread.userAId === userId ? thread.userBId : thread.userAId) : msg.senderId
    if (recipientId !== userId && currentReactions[userId] === emoji) {
      const reactor = await prisma.user.findUnique({ where: { id: userId }, select: { displayName: true } })
      await pushNotification(prisma, {
        userId: recipientId,
        type: 'MESSAGE_RECEIVED',
        title: reactor?.displayName ?? 'New reaction',
        body: `Reacted ${emoji} to your message`,
        refType: 'USER',
        refId: userId,
      })
    }

    emitToThread(msg.threadId, 'message_reaction', { messageId: msgId, reactions: updated.reactions })
    // Also emit to the other user's personal room so they see the reaction
    // even if they are not currently viewing the conversation.
    const otherUserId = thread.userAId === userId ? thread.userBId : thread.userAId
    emitToUser(otherUserId, 'message_reaction', { messageId: msgId, threadId: msg.threadId, reactions: updated.reactions })
    res.json({ ok: true, reactions: updated.reactions })
  } catch (err) { next(err) }
})
