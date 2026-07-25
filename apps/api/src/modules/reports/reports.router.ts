import { Router, type IRouter } from 'express'
import { z } from 'zod'
import type { ReportTargetType } from '@prisma/client'
import { prisma } from '../../lib/prisma'
import { authenticate, type AuthedRequest } from '../../middleware/authenticate'
import { badRequest, tooMany } from '../../lib/http-error'

export const reportsRouter: IRouter = Router()
reportsRouter.use(authenticate)

const reportBody = z.object({
  targetType: z.enum(['USER', 'NEED', 'MESSAGE']),
  targetId: z.string().min(1),
  reason: z.string().min(3).max(500),
})

const DEDUPE_WINDOW_MS = 24 * 60 * 60 * 1000

reportsRouter.post('/', async (req, res, next) => {
  const parsed = reportBody.safeParse(req.body)
  if (!parsed.success) return next(badRequest('Invalid report payload', 'INVALID_BODY'))
  const reporterId = (req as AuthedRequest).userId
  const { targetType, targetId, reason } = parsed.data

  try {
    // No self-reports
    if (targetType === 'USER' && targetId === reporterId) {
      return next(badRequest("You can't report yourself", 'SELF_REPORT'))
    }

    // Target must exist
    const exists = await targetExists(targetType, targetId)
    if (!exists) return next(badRequest('Report target not found', 'TARGET_NOT_FOUND'))

    // Dedupe: within 24h, same reporter cannot re-report the same target while OPEN
    const since = new Date(Date.now() - DEDUPE_WINDOW_MS)
    const dup = await prisma.report.findFirst({
      where: {
        reporterId,
        targetType: targetType as ReportTargetType,
        targetId,
        status: 'OPEN',
        createdAt: { gte: since },
      },
    })
    if (dup) return next(tooMany('You already reported this recently', 'DUPLICATE_REPORT'))

    const created = await prisma.$transaction(async (tx) => {
      const report = await tx.report.create({
        data: {
          reporterId,
          targetType: targetType as ReportTargetType,
          targetId,
          reason,
          status: 'OPEN',
        },
      })
      await tx.reportMeta.create({
        data: {
          reportId: report.id,
          source: 'user',
          detail: { reason } as never,
        },
      })
      return report
    })

    res.status(201).json({ id: created.id })
  } catch (err) { next(err) }
})

async function targetExists(type: 'USER' | 'NEED' | 'MESSAGE', id: string): Promise<boolean> {
  if (type === 'USER') {
    const u = await prisma.user.findUnique({ where: { id }, select: { id: true } })
    return u !== null
  }
  if (type === 'NEED') {
    const n = await prisma.need.findUnique({ where: { id }, select: { id: true } })
    return n !== null
  }
  // MESSAGE — check both DM and thread messages
  const dm = await prisma.dmMessage.findUnique({ where: { id }, select: { id: true } })
  if (dm) return true
  const msg = await prisma.message.findUnique({ where: { id }, select: { id: true } })
  return msg !== null
}
