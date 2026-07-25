import { Router, type IRouter } from 'express'
import { prisma } from '../../lib/prisma'
import { authenticate, type AuthedRequest } from '../../middleware/authenticate'
import { notFound, forbidden, badRequest } from '../../lib/http-error'

export const notificationsRouter: IRouter = Router()

notificationsRouter.use(authenticate)

// GET /notifications?take=30&before=cursor
notificationsRouter.get('/', async (req, res, next) => {
  try {
    const me = (req as unknown as AuthedRequest).userId!
    const take = Math.min(Number(req.query.take) || 30, 100)
    const before = req.query.before as string | undefined

    const rows = await prisma.notification.findMany({
      where: {
        userId: me,
        ...(before ? { createdAt: { lt: new Date(before) } } : {}),
      },
      orderBy: { createdAt: 'desc' },
      take,
    })
    res.json(rows)
  } catch (err) { next(err) }
})

// GET /notifications/count — unread badge
notificationsRouter.get('/count', async (req, res, next) => {
  try {
    const me = (req as unknown as AuthedRequest).userId!
    const unread = await prisma.notification.count({
      where: { userId: me, readAt: null },
    })
    res.json({ unread })
  } catch (err) { next(err) }
})

// POST /notifications/:id/read
notificationsRouter.post('/:id/read', async (req, res, next) => {
  try {
    const me = (req as unknown as AuthedRequest).userId!
    const notif = await prisma.notification.findUnique({ where: { id: req.params.id } })
    if (!notif) return next(notFound('Notification not found'))
    if (notif.userId !== me) return next(forbidden('Not your notification'))
    await prisma.notification.update({
      where: { id: req.params.id },
      data: { readAt: new Date() },
    })
    res.json({ ok: true })
  } catch (err) { next(err) }
})

// POST /notifications/read-all
notificationsRouter.post('/read-all', async (req, res, next) => {
  try {
    const me = (req as unknown as AuthedRequest).userId!
    await prisma.notification.updateMany({
      where: { userId: me, readAt: null },
      data: { readAt: new Date() },
    })
    res.json({ ok: true })
  } catch (err) { next(err) }
})

// ── DELETE /notifications/:id — delete a single notification ──────────
notificationsRouter.delete('/:id', async (req, res, next) => {
  try {
    const me = (req as unknown as AuthedRequest).userId!
    const notif = await prisma.notification.findUnique({ where: { id: req.params.id } })
    if (!notif) return next(notFound('Notification not found'))
    if (notif.userId !== me) return next(forbidden('Not your notification'))
    await prisma.notification.delete({ where: { id: req.params.id } })
    res.json({ ok: true })
  } catch (err) { next(err) }
})

// ── POST /notifications/clear — bulk delete by time range ─────────────
// Body: { "range": "day" | "week" | "all" }
notificationsRouter.post('/clear', async (req, res, next) => {
  try {
    const me = (req as unknown as AuthedRequest).userId!
    const range = (req.body.range as string | undefined)?.toLowerCase()
    if (!range || !['day', 'week', 'all'].includes(range)) {
      return next(badRequest('range must be "day", "week", or "all"'))
    }

    const where: { userId: string; createdAt?: { gte: Date } } = { userId: me }
    if (range === 'day') {
      where.createdAt = { gte: new Date(Date.now() - 24 * 60 * 60 * 1000) }
    } else if (range === 'week') {
      where.createdAt = { gte: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000) }
    }
    // range === 'all' → no date filter, deletes everything

    const result = await prisma.notification.deleteMany({ where })
    res.json({ ok: true, deleted: result.count })
  } catch (err) { next(err) }
})

// ── POST /notifications/clear-selected — delete specific IDs ──────────
// Body: { "ids": ["id1", "id2", ...] }
notificationsRouter.post('/clear-selected', async (req, res, next) => {
  try {
    const me = (req as unknown as AuthedRequest).userId!
    const ids = req.body.ids as string[] | undefined
    if (!ids || !Array.isArray(ids) || ids.length === 0) {
      return next(badRequest('ids must be a non-empty array'))
    }

    const result = await prisma.notification.deleteMany({
      where: { id: { in: ids }, userId: me },
    })
    res.json({ ok: true, deleted: result.count })
  } catch (err) { next(err) }
})

