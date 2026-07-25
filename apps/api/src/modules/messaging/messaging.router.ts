import { Router, type IRouter } from 'express'
import multer from 'multer'
import { prisma } from '../../lib/prisma'
import { authenticate, type AuthedRequest } from '../../middleware/authenticate'
import { badRequest, forbidden, notFound } from '../../lib/http-error'
import { uploadFile, storageKey } from '../../lib/storage'
import { isBlockedBetween, areFriends } from '../friends/friends.service'
import { pushNotification } from '../../lib/notifications'

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

    const result = await Promise.all(
      threads.map(async (t) => {
        const otherId = t.userAId === userId ? t.userBId : t.userAId
        const other = await prisma.user.findUnique({
          where: { id: otherId },
          select: { id: true, displayName: true, profile: { select: { avatarUrl: true } } },
        })
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
      include: { sender: { select: { id: true, displayName: true, profile: { select: { avatarUrl: true } } } } },
    })

    // Mark fetched messages as read
    await prisma.dmMessage.updateMany({
      where: { threadId, senderId: { not: userId }, readAt: null },
      data: { readAt: new Date() },
    })

    res.json(since ? messages : messages.reverse())
  } catch (err) { next(err) }
})

// ── POST /chats/dm/:userId/messages ───────────────────────────────────────────

messagingRouter.post('/dm/:userId/messages', authenticate, upload.single('image'), async (req, res, next) => {
  try {
    const senderId = (req as AuthedRequest).userId!
    const { userId: recipientId } = req.params
    const body = (req.body.body as string | undefined)?.trim() ?? ''

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
        data: { threadId: thread.id, senderId, body: body || '', imageUrl },
        include: {
          sender: { select: { id: true, displayName: true, profile: { select: { avatarUrl: true } } } },
          thread: { select: { id: true } },
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
    res.json({ ok: true })
  } catch (err) { next(err) }
})
