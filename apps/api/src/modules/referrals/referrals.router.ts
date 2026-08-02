import { Router, type IRouter } from 'express'
import { prisma } from '../../lib/prisma'
import { authenticate, type AuthedRequest } from '../../middleware/authenticate'
import { uniqueReferralCode } from '../auth/auth.service'

export const referralsRouter: IRouter = Router()

/**
 * Referral codes are assigned at signup, but every account created before
 * that shipped (and any created through paths that skipped it) has a null
 * code — which showed up in the app as "Refer a Friend" simply never
 * producing a code. Rather than a one-off bulk backfill, mint it lazily the
 * first time the user actually opens the referral screen: it self-heals for
 * old and new accounts alike, and costs one extra write exactly once.
 *
 * Returns the existing code untouched when there already is one.
 */
async function ensureReferralCode(
  userId: string,
  displayName: string,
  existingCode: string | null,
): Promise<string | null> {
  if (existingCode) return existingCode
  try {
    const code = await uniqueReferralCode(displayName)
    const updated = await prisma.user.update({
      where: { id: userId },
      data: { referralCode: code },
      select: { referralCode: true },
    })
    return updated.referralCode
  } catch (err) {
    // Unique-constraint race with a concurrent request: whoever won already
    // stored a code, so re-read rather than failing the whole response.
    console.error('[referrals] failed to mint referral code', userId, err)
    const fresh = await prisma.user.findUnique({
      where: { id: userId },
      select: { referralCode: true },
    })
    return fresh?.referralCode ?? null
  }
}

// GET /referrals/me — my referral code + stats
referralsRouter.get('/me', authenticate, async (req, res, next) => {
  try {
    const userId = (req as AuthedRequest).userId

    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { referralCode: true, displayName: true },
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

    const referralCode = user
      ? await ensureReferralCode(userId!, user.displayName, user.referralCode)
      : null

    res.json({
      referralCode,
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
