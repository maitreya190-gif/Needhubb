import { Router, type IRouter } from 'express'
import { prisma } from '../../lib/prisma'
import { authenticate, type AuthedRequest } from '../../middleware/authenticate'

export const referralsRouter: IRouter = Router()

// GET /referrals/me — my referral code + stats
referralsRouter.get('/me', authenticate, async (req, res, next) => {
  try {
    const userId = (req as AuthedRequest).userId

    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { referralCode: true },
    })

    const referrals = await prisma.referral.findMany({
      where: { referrerId: userId },
      select: {
        id: true,
        status: true,
        activatedAt: true,
        createdAt: true,
        refereeId: true,
      },
      orderBy: { createdAt: 'desc' },
    })

    const refereeIds = referrals.map((r) => r.refereeId)
    const referees = refereeIds.length > 0
      ? await prisma.user.findMany({
          where: { id: { in: refereeIds } },
          select: { id: true, displayName: true },
        })
      : []

    const refereeMap = Object.fromEntries(referees.map((u) => [u.id, u.displayName]))

    const total = referrals.length
    const activated = referrals.filter((r) => r.status === 'ACTIVATED').length
    const pointsEarned = activated * 15

    res.json({
      referralCode: user?.referralCode ?? null,
      stats: { total, activated, pointsEarned },
      referrals: referrals.map((r) => ({
        id: r.id,
        refereeName: refereeMap[r.refereeId] ?? 'Unknown',
        status: r.status,
        activatedAt: r.activatedAt,
        joinedAt: r.createdAt,
      })),
    })
  } catch (err) { next(err) }
})
