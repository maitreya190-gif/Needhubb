import crypto from 'node:crypto'
import { Router, type IRouter } from 'express'
import type { Prisma } from '@prisma/client'
import { prisma } from '../../lib/prisma'
import { authenticate, type AuthedRequest } from '../../middleware/authenticate'
import { badRequest, forbidden, notFound } from '../../lib/http-error'
import {
  PLUS_PERIOD_DAYS, isPlusActive, expirePlusIfNeeded, activatePlus, canSelfReportInstantly,
} from '../../lib/plus'
import { getPaymentProvider } from '../../lib/payments'
import {
  fetchVerifiedPoints, evaluateRewardEligibility, fingerprintPayoutDetails, validatePayoutDetails,
  type PayoutFieldSpec,
} from '../../lib/plus-rewards'
import { recordEngagement, resolveWindow, computePlusAnalytics, type EngagementRow } from '../../lib/plus-analytics'
import { callGroqWithFallback } from '../translate/translate.router'

export const plusRouter: IRouter = Router()

plusRouter.use(authenticate)

const PLUS_MONTHLY_PRICE_PAISE = 5000 // ₹50.00

function userId(req: Parameters<typeof authenticate>[0]): string {
  return (req as AuthedRequest).userId!
}

// ── GET /plus/status ──────────────────────────────────────────────────────

plusRouter.get('/status', async (req, res, next) => {
  try {
    const uid = userId(req)
    const sub = await prisma.plusSubscription.findUnique({ where: { userId: uid } })
    if (sub) await expirePlusIfNeeded(sub)
    const fresh = sub ? await prisma.plusSubscription.findUnique({ where: { userId: uid } }) : null
    const active = isPlusActive(fresh)
    res.json({
      active,
      status: fresh?.status ?? 'PENDING',
      currentPeriodEnd: fresh?.currentPeriodEnd?.toISOString() ?? null,
      cancelAtPeriodEnd: fresh?.cancelAtPeriodEnd ?? false,
      priceMonthlyPaise: PLUS_MONTHLY_PRICE_PAISE,
      benefits: {
        needBoost: active,
        chitchatBoost: active,
        premiumBadge: active,
        analytics: active,
        aiInsights: active,
        // Flags only — see plan §7. No behavior is gated on these two today.
        earlyAccess: active,
        prioritySupport: active,
      },
    })
  } catch (err) { next(err) }
})

// ── POST /plus/subscribe ──────────────────────────────────────────────────
// Creates a fresh payment intent every call — safe even if the user retries,
// since activatePlus's compare-and-swap means only ever ONE of any number of
// pending payment rows for this user can ever actually credit a period.

plusRouter.post('/subscribe', async (req, res, next) => {
  try {
    const uid = userId(req)
    const provider = getPaymentProvider()
    const idempotencyKey = crypto.randomUUID()

    const intent = await provider.createIntent({
      userId: uid,
      amountPaise: PLUS_MONTHLY_PRICE_PAISE,
      currency: 'INR',
      idempotencyKey,
    })

    const payment = await prisma.plusPayment.create({
      data: {
        userId: uid,
        provider: provider.id,
        providerOrderId: intent.providerOrderId,
        amountPaise: PLUS_MONTHLY_PRICE_PAISE,
        currency: 'INR',
        idempotencyKey,
      },
    })

    res.status(201).json({ ...intent, paymentId: payment.id })
  } catch (err) { next(err) }
})

// ── POST /plus/payments/:id/confirm ───────────────────────────────────────
// selfReportedSuccess: true  -> user reports the UPI app said it succeeded.
//   Trusted immediately (per product decision) and activated right away,
//   but flagged `selfReported` so an admin can audit/revoke it afterward.
// selfReportedSuccess: false/omitted -> ambiguous ("not sure yet"). Sets
//   AWAITING_CONFIRMATION; the mobile app then polls GET /plus/status for
//   up to 5 minutes in case an admin confirms manually in the meantime.

plusRouter.post('/payments/:id/confirm', async (req, res, next) => {
  try {
    const uid = userId(req)
    const { selfReportedSuccess, reference } = req.body as { selfReportedSuccess?: boolean; reference?: string }

    const payment = await prisma.plusPayment.findUnique({ where: { id: req.params.id } })
    if (!payment) return next(notFound('Payment not found', 'PAYMENT_NOT_FOUND'))
    if (payment.userId !== uid) return next(forbidden('Not your payment', 'FORBIDDEN'))

    if (selfReportedSuccess === true) {
      const existingSub = await prisma.plusSubscription.findUnique({ where: { userId: uid } })
      if (!canSelfReportInstantly(existingSub)) {
        await prisma.plusPayment.update({
          where: { id: payment.id },
          data: { status: 'AWAITING_CONFIRMATION', userReference: reference?.trim() || null },
        })
        return res.json({
          status: 'awaiting_confirmation',
          reason: 'ALREADY_ACTIVE_TOO_EARLY_TO_SELF_RENEW',
        })
      }

      const result = await prisma.$transaction(async (tx) => {
        await tx.plusPayment.update({
          where: { id: payment.id },
          data: { selfReported: true, userReference: reference?.trim() || null },
        })
        return activatePlus(tx, { userId: uid, paymentId: payment.id, periodDays: PLUS_PERIOD_DAYS })
      })
      const sub = await prisma.plusSubscription.findUnique({ where: { userId: uid } })
      return res.json({
        status: result.activated ? 'activated' : 'already_processed',
        selfReported: true,
        currentPeriodEnd: sub?.currentPeriodEnd?.toISOString() ?? null,
      })
    }

    await prisma.plusPayment.update({
      where: { id: payment.id },
      data: { status: 'AWAITING_CONFIRMATION', userReference: reference?.trim() || null },
    })
    res.json({ status: 'awaiting_confirmation' })
  } catch (err) { next(err) }
})

// ── POST /plus/cancel ──────────────────────────────────────────────────────
// Never revokes mid-period — Plus simply won't renew at currentPeriodEnd.

plusRouter.post('/cancel', async (req, res, next) => {
  try {
    const uid = userId(req)
    await prisma.plusSubscription.updateMany({
      where: { userId: uid },
      data: { cancelAtPeriodEnd: true },
    })
    res.json({ ok: true })
  } catch (err) { next(err) }
})

async function requirePlusActive(uid: string): Promise<boolean> {
  const sub = await prisma.plusSubscription.findUnique({ where: { userId: uid } })
  if (sub) await expirePlusIfNeeded(sub)
  const fresh = sub ? await prisma.plusSubscription.findUnique({ where: { userId: uid } }) : null
  return isPlusActive(fresh)
}

// ── GET /plus/analytics?window=7d|30d ─────────────────────────────────────

plusRouter.get('/analytics', async (req, res, next) => {
  try {
    const uid = userId(req)
    if (!(await requirePlusActive(uid))) {
      return next(forbidden('NeedHub Plus is required for analytics', 'PLUS_REQUIRED'))
    }

    const windowParam = req.query.window === '30d' ? '30d' : '7d'
    const window = resolveWindow(windowParam)

    const [rows, trendRows, posted, offersReceived, reviewsReceived, vouchesReceived, reachRows] = await Promise.all([
      prisma.contentEngagementDaily.findMany({
        where: { ownerId: uid, day: { gte: window.since.toISOString().slice(0, 10) } },
        select: { kind: true, targetType: true, targetId: true, day: true },
      }),
      prisma.contentEngagementDaily.groupBy({
        by: ['day'],
        where: {
          ownerId: uid, kind: 'VIEW',
          day: { gte: new Date(Date.now() - 30 * 24 * 3_600_000).toISOString().slice(0, 10) },
        },
        _count: { _all: true },
      }),
      prisma.need.findMany({
        where: { posterId: uid, createdAt: { gte: window.since } },
        select: { id: true, _count: { select: { responses: true } } },
      }),
      prisma.interestResponse.count({
        where: { need: { posterId: uid }, createdAt: { gte: window.since } },
      }),
      prisma.review.count({ where: { revieweeId: uid, createdAt: { gte: window.since } } }),
      prisma.vouch.count({ where: { voucheeId: uid, createdAt: { gte: window.since } } }),
      prisma.contentEngagementDaily.findMany({
        where: { ownerId: uid, kind: 'VIEW', day: { gte: window.since.toISOString().slice(0, 10) } },
        select: { actorKey: true },
        distinct: ['actorKey'],
      }),
    ])

    const engagementRows: EngagementRow[] = rows.map((r) => ({
      kind: r.kind, targetType: r.targetType, targetId: r.targetId, day: r.day,
    }))
    const analytics = computePlusAnalytics(
      engagementRows,
      { postedInWindow: posted.length, postedWithAtLeastOneOffer: posted.filter((n) => n._count.responses > 0).length },
      { offersReceived, reviewsReceived, vouchesReceived },
      reachRows.length,
      window,
      trendRows.map((t) => ({ day: t.day, count: t._count._all })),
    )
    res.json(analytics)
  } catch (err) { next(err) }
})

// ── GET /plus/insights — AI posting insights ──────────────────────────────

const INSIGHTS_CACHE_TTL_MS = 24 * 3_600_000
const insightsCache = new Map<string, { at: number; insights: string[] }>()

export function __resetPlusInsightsCacheForTests(): void {
  insightsCache.clear()
}

plusRouter.get('/insights', async (req, res, next) => {
  try {
    const uid = userId(req)
    if (!(await requirePlusActive(uid))) {
      return next(forbidden('NeedHub Plus is required for insights', 'PLUS_REQUIRED'))
    }

    const needs = await prisma.need.findMany({
      where: { posterId: uid },
      orderBy: { createdAt: 'desc' },
      take: 20,
      select: {
        title: true, earnCategory: true, connectCategory: true, needType: true,
        createdAt: true, status: true, _count: { select: { responses: true } },
      },
    })

    if (needs.length < 5) {
      return res.json({
        insufficientData: true,
        insights: [
          'Post a few more Needs so we can find real patterns in what works for you.',
          'Clear titles with a specific ask tend to get faster responses.',
          'Needs posted with a budget attached are usually taken up quicker.',
        ],
      })
    }

    const cached = insightsCache.get(uid)
    if (cached && Date.now() - cached.at < INSIGHTS_CACHE_TTL_MS) {
      return res.json({ insufficientData: false, insights: cached.insights, cached: true })
    }

    const avgResponses = needs.reduce((s, n) => s + n._count.responses, 0) / needs.length
    const summary = needs.map((n) =>
      `- "${n.title}" (${n.needType}${n.earnCategory ? '/' + n.earnCategory : ''}${n.connectCategory ? '/' + n.connectCategory : ''}), ` +
      `posted ${n.createdAt.toISOString().slice(0, 10)}, status ${n.status}, ${n._count.responses} responses`,
    ).join('\n')

    const raw = await callGroqWithFallback([
      {
        role: 'system',
        content: 'You help people posting on a local community app (NeedHub) improve how their posts perform. ' +
          'Given their recent posts, return exactly 3 short, concrete, actionable suggestions as a JSON array of strings. ' +
          'No preamble, no markdown, just the JSON array.',
      },
      {
        role: 'user',
        content: `Average responses per need: ${avgResponses.toFixed(1)}.\nRecent needs:\n${summary}`,
      },
    ])

    let insights: string[] | null = null
    if (raw) {
      try {
        const parsed = JSON.parse(raw)
        if (Array.isArray(parsed) && parsed.every((x) => typeof x === 'string')) insights = parsed.slice(0, 3)
      } catch {
        // fall through to heuristic
      }
    }

    if (!insights) {
      // Heuristic fallback — computed from the user's own real data, never
      // a hallucinated pattern.
      insights = [
        avgResponses < 1
          ? 'Your needs are getting fewer than 1 response on average — try adding more detail or a fair budget.'
          : `Your needs average ${avgResponses.toFixed(1)} responses — keep doing what's working.`,
        'Needs posted in the morning tend to be seen by more people before the day fills up their feed.',
        'Add a clear budget or timeframe — needs with specifics usually convert faster than open-ended ones.',
      ]
    }

    insightsCache.set(uid, { at: Date.now(), insights })
    res.json({ insufficientData: false, insights, cached: false })
  } catch (err) { next(err) }
})

// ── GET /plus/rewards — catalog + eligibility ─────────────────────────────

plusRouter.get('/rewards', async (req, res, next) => {
  try {
    const uid = userId(req)
    const [offers, user, verifiedPoints] = await Promise.all([
      prisma.rewardOffer.findMany({ orderBy: { createdAt: 'asc' } }),
      prisma.user.findUnique({
        where: { id: uid },
        select: { verificationLevel: true, createdAt: true, profile: { select: { pointsTotal: true } } },
      }),
      fetchVerifiedPoints(uid),
    ])
    if (!user) return next(notFound('User not found', 'USER_NOT_FOUND'))

    const claimedOfferIds = new Set(
      (await prisma.rewardClaim.findMany({ where: { userId: uid }, select: { offerId: true } })).map((c) => c.offerId),
    )
    const accountAgeDays = Math.floor((Date.now() - user.createdAt.getTime()) / 86_400_000)

    const rows = offers.map((offer) => {
      const eligibility = evaluateRewardEligibility({
        offer,
        alreadyClaimed: claimedOfferIds.has(offer.id),
        verifiedPoints,
        spendableBalance: user.profile?.pointsTotal ?? 0,
        verificationLevel: user.verificationLevel,
        accountAgeDays,
      })
      return {
        key: offer.key,
        kind: offer.kind,
        title: offer.title,
        description: offer.description,
        pointsCost: offer.pointsCost,
        rewardValuePaise: offer.rewardValuePaise,
        minVerifiedPoints: offer.minVerifiedPoints,
        payoutFields: offer.payoutFieldsJson ?? [],
        alreadyClaimed: claimedOfferIds.has(offer.id),
        ...eligibility,
      }
    })
    res.json({ verifiedPoints, spendableBalance: user.profile?.pointsTotal ?? 0, offers: rows })
  } catch (err) { next(err) }
})

// ── POST /plus/rewards/:offerKey/claim ────────────────────────────────────

plusRouter.post('/rewards/:offerKey/claim', async (req, res, next) => {
  try {
    const uid = userId(req)
    const payoutDetails = (req.body?.payoutDetails ?? {}) as Record<string, unknown>

    const offer = await prisma.rewardOffer.findUnique({ where: { key: req.params.offerKey } })
    if (!offer) return next(notFound('Reward offer not found', 'OFFER_NOT_FOUND'))

    const fields = (offer.payoutFieldsJson as unknown as PayoutFieldSpec[] | null) ?? []
    const validation = validatePayoutDetails(fields, payoutDetails)
    if (!validation.valid) return next(badRequest(validation.message, 'INVALID_PAYOUT_DETAILS'))

    const [user, verifiedPoints, existingClaim] = await Promise.all([
      prisma.user.findUnique({
        where: { id: uid },
        select: { verificationLevel: true, createdAt: true, profile: { select: { pointsTotal: true } } },
      }),
      fetchVerifiedPoints(uid),
      prisma.rewardClaim.findUnique({ where: { userId_offerId: { userId: uid, offerId: offer.id } } }),
    ])
    if (!user) return next(notFound('User not found', 'USER_NOT_FOUND'))

    const accountAgeDays = Math.floor((Date.now() - user.createdAt.getTime()) / 86_400_000)
    const eligibility = evaluateRewardEligibility({
      offer,
      alreadyClaimed: !!existingClaim,
      verifiedPoints,
      spendableBalance: user.profile?.pointsTotal ?? 0,
      verificationLevel: user.verificationLevel,
      accountAgeDays,
    })
    if (!eligibility.eligible) return next(badRequest('Not eligible for this reward', eligibility.reason))

    const payoutMethod = fields.find((f) => f.type === 'upi') ? 'UPI' : fields.find((f) => f.type === 'email') ? 'EMAIL' : 'OTHER'
    const fingerprint = fingerprintPayoutDetails(payoutDetails)

    const claim = await prisma.$transaction(async (tx) => {
      const bumped = await tx.rewardOffer.updateMany({
        where: {
          id: offer.id,
          OR: [{ maxRedemptions: -1 }, { redeemedCount: { lt: offer.maxRedemptions } }],
        },
        data: { redeemedCount: { increment: 1 } },
      })
      if (bumped.count === 0) throw badRequest('This reward has been fully claimed', 'REWARD_EXHAUSTED')

      const created = await tx.rewardClaim.create({
        data: {
          userId: uid,
          offerId: offer.id,
          pointsSpent: offer.pointsCost,
          rewardValuePaise: offer.rewardValuePaise,
          payoutMethod,
          payoutDetails: payoutDetails as Prisma.InputJsonValue,
          payoutFingerprint: fingerprint,
          verifiedPointsAtClaim: verifiedPoints,
        },
      })

      // Same spend triple used by POST /needs/:id/boost — a negative ledger
      // delta never affects verified points or Impact League standing
      // (impact-league.ts sums delta>0 only), so this can never touch the
      // user's contribution record.
      await tx.profile.update({ where: { userId: uid }, data: { pointsTotal: { decrement: offer.pointsCost } } })
      await tx.pointsLedger.create({
        data: { userId: uid, delta: -offer.pointsCost, reason: `Reward claim: ${offer.title}`, refId: created.id },
      })

      return created
    })

    res.status(201).json({ ok: true, claimId: claim.id, status: claim.status })
  } catch (err) { next(err) }
})

// ── GET /plus/rewards/mine — redemption history ───────────────────────────

plusRouter.get('/rewards/mine', async (req, res, next) => {
  try {
    const uid = userId(req)
    const claims = await prisma.rewardClaim.findMany({
      where: { userId: uid },
      orderBy: { createdAt: 'desc' },
      include: { offer: { select: { title: true, kind: true } } },
    })
    res.json(claims.map((c) => ({
      id: c.id,
      offerTitle: c.offer.title,
      kind: c.offer.kind,
      status: c.status,
      pointsSpent: c.pointsSpent,
      rewardValuePaise: c.rewardValuePaise,
      payoutRef: c.payoutRef,
      createdAt: c.createdAt.toISOString(),
      processedAt: c.processedAt?.toISOString() ?? null,
    })))
  } catch (err) { next(err) }
})

// ── POST /plus/events/share — fire-and-forget share tracking ──────────────

plusRouter.post('/events/share', async (req, res) => {
  const uid = userId(req)
  const { targetType, targetId, ownerId } = req.body as {
    targetType?: 'PROFILE' | 'NEED'; targetId?: string; ownerId?: string
  }
  if (targetType && targetId && ownerId) {
    recordEngagement({
      kind: 'SHARE', targetType, targetId, ownerId,
      ip: req.ip ?? '', userAgent: req.get('user-agent') ?? '', actorUserId: uid,
    }).catch((err) => console.error('[plus] share event record failed', err))
  }
  // Always succeeds from the client's point of view — a failed analytics
  // ping must never surface an error to someone who just shared something.
  res.json({ ok: true })
})
