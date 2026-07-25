import { Router, type IRouter } from 'express'
import { prisma } from '../../lib/prisma'
import { authenticate, type AuthedRequest } from '../../middleware/authenticate'
import { notFound, forbidden } from '../../lib/http-error'

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
