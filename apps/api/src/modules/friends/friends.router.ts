import { Router, type IRouter } from 'express'
import { z } from 'zod'
import { prisma } from '../../lib/prisma'
import { authenticate, type AuthedRequest } from '../../middleware/authenticate'
import { pushNotification } from '../../lib/notifications'
import { badRequest, forbidden, notFound, conflict } from '../../lib/http-error'
import { sortedPair, isBlockedBetween, areFriends, pendingRequestBetween } from './friends.service'

export const friendsRouter: IRouter = Router()

friendsRouter.use(authenticate)

const sendReqBody = z.object({ toUserId: z.string().min(1) })
const blockBody = z.object({ userId: z.string().min(1) })

// ─── Friend Requests ─────────────────────────────────────────────────────────

friendsRouter.post('/requests', async (req, res, next) => {
  try {
    const me = (req as unknown as AuthedRequest).userId!
    const parsed = sendReqBody.safeParse(req.body)
    if (!parsed.success) return next(badRequest('Invalid body', 'INVALID_BODY'))
    const { toUserId } = parsed.data

    if (toUserId === me) return next(badRequest('Cannot friend yourself', 'SELF_TARGET'))

    const target = await prisma.user.findUnique({ where: { id: toUserId }, select: { id: true } })
    if (!target) return next(notFound('User not found', 'USER_NOT_FOUND'))

    if (await isBlockedBetween(me, toUserId)) return next(forbidden('Blocked', 'BLOCKED'))
    if (await areFriends(me, toUserId)) return next(conflict('Already friends', 'ALREADY_FRIENDS'))

    const existing = await pendingRequestBetween(me, toUserId)
    if (existing) return next(conflict('Request already exists', 'REQUEST_EXISTS'))

    const request = await prisma.$transaction(async (tx) => {
      const created = await tx.friendRequest.create({
        data: { fromUserId: me, toUserId, status: 'PENDING' },
      })
      const fromUser = await tx.user.findUnique({
        where: { id: me }, select: { displayName: true },
      })
      await pushNotification(tx, {
        userId: toUserId,
        type: 'FRIEND_REQUEST_RECEIVED',
        title: 'New friend request',
        body: `${fromUser?.displayName ?? 'Someone'} sent you a friend request`,
        refType: 'FRIEND_REQUEST',
        refId: created.id,
      })
      return created
    })

    res.status(201).json(request)
  } catch (err) { next(err) }
})

friendsRouter.get('/requests', async (req, res, next) => {
  try {
    const me = (req as unknown as AuthedRequest).userId!
    const [inbox, outbox] = await Promise.all([
      prisma.friendRequest.findMany({
        where: { toUserId: me, status: 'PENDING' },
        include: { },
        orderBy: { createdAt: 'desc' },
      }),
      prisma.friendRequest.findMany({
        where: { fromUserId: me, status: 'PENDING' },
        orderBy: { createdAt: 'desc' },
      }),
    ])

    // Attach the counterparty user (minimal).
    const otherIds = new Set<string>()
    inbox.forEach((r) => otherIds.add(r.fromUserId))
    outbox.forEach((r) => otherIds.add(r.toUserId))
    const users = await prisma.user.findMany({
      where: { id: { in: Array.from(otherIds) } },
      select: {
        id: true, displayName: true,
        profile: { select: { avatarUrl: true } },
      },
    })
    const userMap = new Map(users.map((u) => [u.id, u]))

    res.json({
      inbox: inbox.map((r) => ({ ...r, other: userMap.get(r.fromUserId) })),
      outbox: outbox.map((r) => ({ ...r, other: userMap.get(r.toUserId) })),
    })
  } catch (err) { next(err) }
})

friendsRouter.post('/requests/:id/accept', async (req, res, next) => {
  try {
    const me = (req as unknown as AuthedRequest).userId!
    const { id } = req.params

    const result = await prisma.$transaction(async (tx) => {
      const request = await tx.friendRequest.findUnique({ where: { id } })
      if (!request) throw notFound('Request not found', 'NOT_FOUND')
      if (request.toUserId !== me) throw forbidden('Not your request', 'FORBIDDEN')
      if (request.status !== 'PENDING') throw conflict('Already resolved', 'RESOLVED')

      if (await isBlockedBetween(request.fromUserId, request.toUserId)) {
        throw forbidden('Blocked', 'BLOCKED')
      }

      await tx.friendRequest.update({ where: { id }, data: { status: 'ACCEPTED' } })
      // Auto-accept the opposite-direction pending request too (mutual race).
      await tx.friendRequest.updateMany({
        where: {
          status: 'PENDING',
          fromUserId: request.toUserId,
          toUserId: request.fromUserId,
        },
        data: { status: 'ACCEPTED' },
      })

      const [a, b] = sortedPair(request.fromUserId, request.toUserId)
      try {
        await tx.friendship.create({ data: { userAId: a, userBId: b } })
      } catch { /* already-exists race is fine */ }

      const meUser = await tx.user.findUnique({
        where: { id: me }, select: { displayName: true },
      })
      await pushNotification(tx, {
        userId: request.fromUserId,
        type: 'FRIEND_REQUEST_ACCEPTED',
        title: 'Friend request accepted',
        body: `${meUser?.displayName ?? 'Someone'} accepted your friend request`,
        refType: 'USER',
        refId: me,
      })

      return request
    })

    res.json({ ok: true, request: result })
  } catch (err) { next(err) }
})

friendsRouter.post('/requests/:id/decline', async (req, res, next) => {
  try {
    const me = (req as unknown as AuthedRequest).userId!
    const request = await prisma.friendRequest.findUnique({ where: { id: req.params.id } })
    if (!request) return next(notFound('Request not found'))
    if (request.toUserId !== me) return next(forbidden('Not your request'))
    if (request.status !== 'PENDING') return next(conflict('Already resolved'))
    await prisma.friendRequest.update({
      where: { id: req.params.id },
      data: { status: 'DECLINED' },
    })
    res.json({ ok: true })
  } catch (err) { next(err) }
})

friendsRouter.delete('/requests/:id', async (req, res, next) => {
  try {
    const me = (req as unknown as AuthedRequest).userId!
    const request = await prisma.friendRequest.findUnique({ where: { id: req.params.id } })
    if (!request) return next(notFound('Request not found'))
    if (request.fromUserId !== me) return next(forbidden('Not your request'))
    if (request.status !== 'PENDING') return next(conflict('Already resolved'))
    await prisma.friendRequest.update({
      where: { id: req.params.id },
      data: { status: 'CANCELED' },
    })
    res.json({ ok: true })
  } catch (err) { next(err) }
})

// ─── Friends ─────────────────────────────────────────────────────────────────

friendsRouter.get('/', async (req, res, next) => {
  try {
    const me = (req as unknown as AuthedRequest).userId!
    const rows = await prisma.friendship.findMany({
      where: { OR: [{ userAId: me }, { userBId: me }] },
      orderBy: { createdAt: 'desc' },
    })
    const otherIds = rows.map((r) => (r.userAId === me ? r.userBId : r.userAId))
    const users = await prisma.user.findMany({
      where: { id: { in: otherIds } },
      select: {
        id: true, displayName: true,
        profile: { select: { avatarUrl: true, bio: true } },
      },
    })
    res.json(users)
  } catch (err) { next(err) }
})

friendsRouter.delete('/:userId', async (req, res, next) => {
  try {
    const me = (req as unknown as AuthedRequest).userId!
    const [a, b] = sortedPair(me, req.params.userId)
    await prisma.friendship.deleteMany({ where: { userAId: a, userBId: b } })
    res.json({ ok: true })
  } catch (err) { next(err) }
})

// ─── Blocks ──────────────────────────────────────────────────────────────────

friendsRouter.post('/blocks', async (req, res, next) => {
  try {
    const me = (req as unknown as AuthedRequest).userId!
    const parsed = blockBody.safeParse(req.body)
    if (!parsed.success) return next(badRequest('Invalid body', 'INVALID_BODY'))
    const { userId } = parsed.data
    if (userId === me) return next(badRequest('Cannot block yourself', 'SELF_TARGET'))

    await prisma.$transaction(async (tx) => {
      // Upsert idempotent.
      const existing = await tx.block.findFirst({
        where: { blockerId: me, blockedId: userId },
        select: { id: true },
      })
      if (!existing) {
        await tx.block.create({ data: { blockerId: me, blockedId: userId } })
      }

      // Kill any friendship.
      const [a, b] = sortedPair(me, userId)
      await tx.friendship.deleteMany({ where: { userAId: a, userBId: b } })

      // Cancel any pending friend requests between the pair.
      await tx.friendRequest.updateMany({
        where: {
          status: 'PENDING',
          OR: [
            { fromUserId: me, toUserId: userId },
            { fromUserId: userId, toUserId: me },
          ],
        },
        data: { status: 'CANCELED' },
      })
    })

    res.status(204).end()
  } catch (err) { next(err) }
})

friendsRouter.delete('/blocks/:userId', async (req, res, next) => {
  try {
    const me = (req as unknown as AuthedRequest).userId!
    await prisma.block.deleteMany({
      where: { blockerId: me, blockedId: req.params.userId },
    })
    res.json({ ok: true })
  } catch (err) { next(err) }
})

friendsRouter.get('/blocks', async (req, res, next) => {
  try {
    const me = (req as unknown as AuthedRequest).userId!
    const blocks = await prisma.block.findMany({
      where: { blockerId: me },
      orderBy: { createdAt: 'desc' },
    })
    const users = await prisma.user.findMany({
      where: { id: { in: blocks.map((b) => b.blockedId) } },
      select: {
        id: true, displayName: true,
        profile: { select: { avatarUrl: true } },
      },
    })
    res.json(users)
  } catch (err) { next(err) }
})
