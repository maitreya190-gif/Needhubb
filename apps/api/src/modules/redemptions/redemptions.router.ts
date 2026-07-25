import { Router, type IRouter } from 'express'
import crypto from 'node:crypto'
import { prisma } from '../../lib/prisma'
import { authenticate, type AuthedRequest } from '../../middleware/authenticate'
import { pushNotification } from '../../lib/notifications'
import { notFound, badRequest } from '../../lib/http-error'

export const redemptionsRouter: IRouter = Router()

// GET /redemptions/catalog — active items (public).
redemptionsRouter.get('/catalog', async (_req, res, next) => {
  try {
    const items = await prisma.redemptionItem.findMany({
      where: { active: true },
      orderBy: { pointsCost: 'asc' },
    })
    res.json(items)
  } catch (err) { next(err) }
})

// POST /redemptions/:itemId/redeem — spend points, get a code.
redemptionsRouter.post('/:itemId/redeem', authenticate, async (req, res, next) => {
  try {
    const me = (req as unknown as AuthedRequest).userId!
    const itemId = req.params.itemId

    const result = await prisma.$transaction(async (tx) => {
      const item = await tx.redemptionItem.findUnique({ where: { id: itemId } })
      if (!item || !item.active) throw notFound('Item not available', 'ITEM_UNAVAILABLE')

      if (item.stock === 0) throw badRequest('Out of stock', 'OUT_OF_STOCK')

      const profile = await tx.profile.findUnique({
        where: { userId: me }, select: { pointsTotal: true },
      })
      const balance = profile?.pointsTotal ?? 0
      if (balance < item.pointsCost) {
        const err: any = new Error('Insufficient points')
        err.status = 402
        err.code = 'INSUFFICIENT_POINTS'
        throw err
      }

      // Decrement stock if bounded (-1 means unlimited).
      if (item.stock > 0) {
        await tx.redemptionItem.update({
          where: { id: itemId },
          data: { stock: { decrement: 1 } },
        })
      }

      // Debit points.
      await tx.pointsLedger.create({
        data: {
          userId: me,
          delta: -item.pointsCost,
          reason: `Redeem: ${item.title}`,
          refId: itemId,
        },
      })
      await tx.profile.update({
        where: { userId: me },
        data: { pointsTotal: { decrement: item.pointsCost } },
      })

      const code = crypto.randomBytes(4).toString('hex').toUpperCase()
      const redemption = await tx.redemption.create({
        data: {
          userId: me, itemId, code, status: 'PENDING',
        },
      })

      await pushNotification(tx, {
        userId: me,
        type: 'REDEMPTION_READY',
        title: 'Redemption ready',
        body: `Your code for "${item.title}" is ${code}`,
        refType: 'REDEMPTION', refId: redemption.id,
      })

      return { redemption, item, newBalance: balance - item.pointsCost }
    })

    res.status(201).json(result)
  } catch (err: any) {
    if (err.status && err.code) return res.status(err.status).json({ error: err.message, code: err.code })
    next(err)
  }
})

// GET /redemptions/mine — my history.
redemptionsRouter.get('/mine', authenticate, async (req, res, next) => {
  try {
    const me = (req as unknown as AuthedRequest).userId!
    const rows = await prisma.redemption.findMany({
      where: { userId: me },
      include: { item: true },
      orderBy: { createdAt: 'desc' },
    })
    res.json(rows)
  } catch (err) { next(err) }
})
