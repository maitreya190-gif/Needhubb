import { Router, type Router as ExpressRouter } from 'express'
import { prisma } from '../../lib/prisma'
import { pushNotification } from '../../lib/notifications'
import { activatePlus } from '../../lib/plus'
import { badRequest, notFound } from '../../lib/http-error'

export const adminRouter: ExpressRouter = Router()

// ── Stats overview ────────────────────────────────────────────────────────────

adminRouter.get('/stats', async (_req, res) => {
  const [users, needs, pendingCerts, openReports, pendingAdInquiries, pendingRewardClaims, pendingPlusPayments] = await Promise.all([
    prisma.user.count(),
    prisma.need.count(),
    prisma.certificate.count({ where: { status: 'PENDING_REVIEW' } }),
    prisma.report.count({ where: { status: 'OPEN' } }),
    prisma.adInquiry.count({ where: { status: 'PENDING' } }),
    prisma.rewardClaim.count({ where: { status: 'PENDING' } }),
    prisma.plusPayment.count({ where: { status: 'AWAITING_CONFIRMATION' } }),
  ])
  res.json({ users, needs, pendingCerts, openReports, pendingAdInquiries, pendingRewardClaims, pendingPlusPayments })
})

// ── Certificates ──────────────────────────────────────────────────────────────

adminRouter.get('/certificates', async (req, res) => {
  const status = (req.query.status as string) || 'PENDING_REVIEW'
  const certs = await prisma.certificate.findMany({
    where: { status: status as any },
    include: { user: { select: { id: true, username: true, displayName: true, email: true } } },
    orderBy: { createdAt: 'desc' },
  })
  res.json(certs)
})

adminRouter.patch('/certificates/:id', async (req, res, next) => {
  const { id } = req.params
  const { status, pointsAwarded } = req.body as {
    status: 'APPROVED' | 'REJECTED'
    pointsAwarded?: number
  }

  try {
    const result = await prisma.$transaction(async (tx) => {
      // Read the current status before updating to prevent duplicate point awards.
      const existing = await tx.certificate.findUniqueOrThrow({ where: { id }, select: { status: true, userId: true, type: true } })
      const wasAlreadyApproved = existing.status === 'APPROVED'

      const cert = await tx.certificate.update({
        where: { id },
        data: { status, pointsAwarded: pointsAwarded ?? null },
      })

      if (status === 'APPROVED' && !wasAlreadyApproved && pointsAwarded && pointsAwarded > 0) {
        await tx.pointsLedger.create({
          data: {
            userId: cert.userId,
            delta: pointsAwarded,
            reason: `Certificate approved: ${cert.type}`,
            refId: cert.id,
          },
        })
        await tx.profile.upsert({
          where: { userId: cert.userId },
          update: { pointsTotal: { increment: pointsAwarded } },
          create: { userId: cert.userId, pointsTotal: pointsAwarded },
        })
        await pushNotification(tx, {
          userId: cert.userId,
          type: 'CERT_APPROVED',
          title: 'Certificate approved!',
          body: `Your ${cert.type.replace(/_/g, ' ').toLowerCase()} certificate was approved. You earned ${pointsAwarded} points.`,
          refType: 'CERTIFICATE',
          refId: cert.id,
        })
      } else if (status === 'REJECTED') {
        await pushNotification(tx, {
          userId: cert.userId,
          type: 'CERT_REJECTED',
          title: 'Certificate not approved',
          body: `Your ${cert.type.replace(/_/g, ' ').toLowerCase()} certificate could not be verified. You may resubmit with clearer documentation.`,
          refType: 'CERTIFICATE',
          refId: cert.id,
        })
      }

      return cert
    })

    res.json(result)
  } catch (err) { next(err) }
})

// ── Reports ───────────────────────────────────────────────────────────────────

adminRouter.get('/reports', async (req, res) => {
  const targetType = req.query.targetType as string | undefined
  const status = (req.query.status as string) || 'OPEN'
  const source = req.query.source as string | undefined

  const reports = await prisma.report.findMany({
    where: {
      status: status as any,
      ...(targetType ? { targetType: targetType as any } : {}),
      ...(source ? { meta: { source } } : {}),
    },
    include: {
      reporter: { select: { id: true, username: true, displayName: true, email: true } },
      meta: true,
    },
    orderBy: { createdAt: 'desc' },
  })
  res.json(await enrichReportsWithTargets(reports))
})

// Dedicated queue for auto-flagged content so admins can triage them first.
adminRouter.get('/moderation/flags', async (req, res) => {
  const source = (req.query.source as string) || 'moderation_hard'
  const status = (req.query.status as string) || 'OPEN'
  const reports = await prisma.report.findMany({
    where: { status: status as any, meta: { source } },
    include: {
      reporter: { select: { id: true, username: true, displayName: true, email: true } },
      meta: true,
    },
    orderBy: { createdAt: 'desc' },
  })
  res.json(await enrichReportsWithTargets(reports))
})

/**
 * For each report, resolve the target's actual content so admins see what was
 * flagged instead of an opaque id. For MESSAGE reports, also attaches the last
 * 20 messages from the thread so admins have full context.
 */
async function enrichReportsWithTargets(reports: any[]) {
  return Promise.all(
    reports.map(async (r) => {
      let target: Record<string, any> | null = null

      if (r.targetType === 'USER') {
        const u = await prisma.user.findUnique({
          where: { id: r.targetId },
          select: { id: true, username: true, displayName: true, email: true },
        })
        if (u) {
          target = { kind: 'USER', ...u }
          // If this report came from a conversation, fetch last 20 messages for context.
          const threadId = (r.meta?.detail as any)?.threadId as string | undefined
          if (threadId) {
            const contextMessages = await prisma.dmMessage.findMany({
              where: { threadId },
              include: { sender: { select: { id: true, username: true, displayName: true } } },
              orderBy: { createdAt: 'desc' },
              take: 20,
            })
            target.contextMessages = contextMessages.reverse()
            target.threadId = threadId
          }
        }
      } else if (r.targetType === 'NEED') {
        if (r.targetId.startsWith('pending:')) {
          const posterId = r.targetId.slice('pending:'.length)
          const poster = await prisma.user.findUnique({
            where: { id: posterId },
            select: { id: true, username: true, displayName: true },
          })
          target = {
            kind: 'NEED',
            pending: true,
            posterId,
            posterName: poster?.username ?? poster?.displayName ?? 'Unknown',
            blockedText: (r.meta?.detail as any)?.text ?? null,
          }
        } else {
          const need = await prisma.need.findUnique({
            where: { id: r.targetId },
            select: {
              id: true, title: true, description: true,
              needType: true, status: true,
              poster: { select: { id: true, username: true, displayName: true } },
            },
          })
          if (need) {
            target = {
              kind: 'NEED',
              id: need.id,
              title: need.title,
              description: need.description,
              needType: need.needType,
              status: need.status,
              posterId: need.poster.id,
              posterName: need.poster.username ?? need.poster.displayName,
            }
          }
        }
      } else if (r.targetType === 'MESSAGE') {
        const dm = await prisma.dmMessage.findUnique({
          where: { id: r.targetId },
          select: {
            id: true, body: true, imageUrl: true, createdAt: true,
            threadId: true,
            sender: { select: { id: true, username: true, displayName: true } },
          },
        })
        if (dm) {
          // Fetch last 20 messages from the thread for admin context.
          const contextMessages = await prisma.dmMessage.findMany({
            where: { threadId: dm.threadId },
            include: { sender: { select: { id: true, username: true, displayName: true } } },
            orderBy: { createdAt: 'desc' },
            take: 20,
          })
          target = {
            kind: 'MESSAGE',
            id: dm.id,
            body: dm.body,
            imageUrl: dm.imageUrl,
            createdAt: dm.createdAt,
            senderId: dm.sender.id,
            senderName: dm.sender.username ?? dm.sender.displayName,
            contextMessages: contextMessages.reverse(),
          }
        }
      }

      return { ...r, target }
    }),
  )
}

adminRouter.patch('/reports/:id/resolve', async (req, res, next) => {
  const { id } = req.params
  const { action, message } = req.body as {
    action: 'dismiss' | 'warn' | 'warn_user' | 'ban_user' | 'remove_need' | 'remove_message'
    message?: string
  }

  try {
    const report = await prisma.$transaction(async (tx) => {
      const updated = await tx.report.update({
        where: { id },
        data: { status: 'RESOLVED' },
      })

      // Normalize warn_user (sent by admin portal) → warn (internal name).
      const act = action === 'warn_user' ? 'warn' : action

      if (act === 'warn') {
        let warnUserId: string | null = null
        if (updated.targetType === 'USER') {
          warnUserId = updated.targetId
        } else if (updated.targetType === 'NEED') {
          if (updated.targetId.startsWith('pending:')) {
            warnUserId = updated.targetId.slice('pending:'.length)
          } else {
            const need = await tx.need.findUnique({
              where: { id: updated.targetId },
              select: { posterId: true },
            })
            warnUserId = need?.posterId ?? null
          }
        } else if (updated.targetType === 'MESSAGE') {
          const dm = await tx.dmMessage.findUnique({
            where: { id: updated.targetId },
            select: { senderId: true },
          })
          warnUserId = dm?.senderId ?? null
        }

        if (warnUserId) {
          await pushNotification(tx, {
            userId: warnUserId,
            type: 'REPORT_ACTIONED',
            title: 'Warning from moderators',
            body: message?.trim() || 'Your content was flagged and reviewed by our team. Please follow community guidelines.',
            refType: 'REPORT',
            refId: id,
          })
        }
      } else if (act === 'ban_user' && updated.targetType === 'USER') {
        await tx.user.delete({ where: { id: updated.targetId } })
      } else if (act === 'remove_need' && updated.targetType === 'NEED') {
        const need = await tx.need.findUnique({
          where: { id: updated.targetId },
          select: { posterId: true, title: true },
        })
        if (need) {
          await pushNotification(tx, {
            userId: need.posterId,
            type: 'REPORT_ACTIONED',
            title: 'Your post was removed',
            body: `Your post "${need.title}" was removed for violating community guidelines.`,
            refType: 'REPORT',
            refId: id,
          })
          await tx.need.delete({ where: { id: updated.targetId } })
        }
      } else if (act === 'remove_message' && updated.targetType === 'MESSAGE') {
        const dm = await tx.dmMessage.findUnique({
          where: { id: updated.targetId },
          select: { id: true, senderId: true },
        })
        if (dm) {
          await pushNotification(tx, {
            userId: dm.senderId,
            type: 'REPORT_ACTIONED',
            title: 'Message removed',
            body: 'One of your messages was removed for violating community guidelines.',
            refType: 'REPORT',
            refId: id,
          })
          await tx.dmMessage.delete({ where: { id: updated.targetId } })
        } else {
          await tx.message.deleteMany({ where: { id: updated.targetId } })
        }
      }

      return updated
    })

    res.json({ ok: true, report })
  } catch (err) { next(err) }
})

// ── Users ─────────────────────────────────────────────────────────────────────

adminRouter.get('/users', async (req, res) => {
  const search = req.query.search as string | undefined
  const take = Math.min(Number(req.query.take) || 50, 200)
  const skip = Number(req.query.skip) || 0

  const users = await prisma.user.findMany({
    where: search
      ? {
          OR: [
            { displayName: { contains: search, mode: 'insensitive' } },
            { email: { contains: search, mode: 'insensitive' } },
          ],
        }
      : undefined,
    select: {
      id: true,
      username: true,
      displayName: true,
      email: true,
      phone: true,
      verificationLevel: true,
      createdAt: true,
      _count: { select: { needs: true, reports: true } },
    },
    orderBy: { createdAt: 'desc' },
    take,
    skip,
  })
  res.json(users)
})

adminRouter.delete('/users/:id', async (req, res) => {
  await prisma.user.delete({ where: { id: req.params.id } })
  res.json({ ok: true })
})

// ── Needs ─────────────────────────────────────────────────────────────────────

adminRouter.get('/needs', async (req, res) => {
  const status = req.query.status as string | undefined
  const take = Math.min(Number(req.query.take) || 50, 200)
  const skip = Number(req.query.skip) || 0

  const needs = await prisma.need.findMany({
    where: status ? { status: status as any } : undefined,
    include: {
      poster: { select: { id: true, username: true, displayName: true, email: true } },
    },
    orderBy: { createdAt: 'desc' },
    take,
    skip,
  })
  res.json(needs)
})

adminRouter.delete('/needs/:id', async (req, res) => {
  await prisma.need.delete({ where: { id: req.params.id } })
  res.json({ ok: true })
})

// ── Ad Inquiries ──────────────────────────────────────────────────────────────

adminRouter.get('/ad-inquiries', async (req, res) => {
  const status = req.query.status as string | undefined
  const inquiries = await prisma.adInquiry.findMany({
    where: status ? { status: status as any } : undefined,
    orderBy: { createdAt: 'desc' },
    take: 100,
  })
  res.json(inquiries)
})

adminRouter.patch('/ad-inquiries/:id', async (req, res, next) => {
  const { id } = req.params
  const { status, adminNotes } = req.body as { status?: string; adminNotes?: string }
  try {
    const updated = await prisma.adInquiry.update({
      where: { id },
      data: {
        ...(status ? { status: status as any } : {}),
        ...(adminNotes !== undefined ? { adminNotes } : {}),
      },
    })
    res.json(updated)
  } catch (err) { next(err) }
})

adminRouter.delete('/ad-inquiries/:id', async (req, res, next) => {
  try {
    await prisma.adInquiry.delete({ where: { id: req.params.id } })
    res.json({ success: true })
  } catch (err) { next(err) }
})

// ── NeedHub Plus: reward claims ─────────────────────────────────────────────
// Where a launch-cashback (or later, voucher/gift-card) claim surfaces for
// review — same "queue + pending count" pattern as ad inquiries, since
// adminAuth has no per-admin identity to push a notification to.

adminRouter.get('/reward-claims', async (req, res) => {
  const status = req.query.status as string | undefined
  const claims = await prisma.rewardClaim.findMany({
    where: status ? { status: status as any } : undefined,
    orderBy: { createdAt: 'desc' },
    take: 100,
    include: {
      user: { select: { id: true, displayName: true, email: true, phone: true, username: true } },
      offer: { select: { title: true, kind: true } },
    },
  })
  // "N other claims use this payout id" — surfaced for human judgment, never
  // auto-rejected on (families legitimately share a UPI id).
  const fingerprints = Array.from(new Set(claims.map((c) => c.payoutFingerprint)))
  const counts = fingerprints.length > 0
    ? await prisma.rewardClaim.groupBy({
        by: ['payoutFingerprint'],
        where: { payoutFingerprint: { in: fingerprints } },
        _count: { _all: true },
      })
    : []
  const countByFingerprint = new Map(counts.map((c) => [c.payoutFingerprint, c._count._all]))
  res.json(claims.map((c) => ({
    ...c,
    duplicatePayoutCount: Math.max(0, (countByFingerprint.get(c.payoutFingerprint) ?? 1) - 1),
  })))
})

adminRouter.patch('/reward-claims/:id', async (req, res, next) => {
  const { id } = req.params
  const { status, adminNotes, payoutRef } = req.body as { status?: string; adminNotes?: string; payoutRef?: string }
  try {
    const claim = await prisma.rewardClaim.findUnique({ where: { id } })
    if (!claim) return next(notFound('Claim not found', 'CLAIM_NOT_FOUND'))

    const updated = await prisma.$transaction(async (tx) => {
      const result = await tx.rewardClaim.update({
        where: { id },
        data: {
          ...(status ? { status: status as any } : {}),
          ...(adminNotes !== undefined ? { adminNotes } : {}),
          ...(payoutRef !== undefined ? { payoutRef } : {}),
          ...(status === 'PAID' || status === 'REJECTED' ? { processedAt: new Date() } : {}),
        },
      })
      // Reuses the existing REDEMPTION_READY type (no enum change) — the
      // mobile navigator's REDEMPTION_READY branch is additively extended
      // with a refType === 'REWARD_CLAIM' check ahead of it, so real
      // catalog redemptions are unaffected.
      if (status === 'PAID') {
        await pushNotification(tx, {
          userId: claim.userId,
          type: 'REDEMPTION_READY',
          title: 'Your NeedHub reward is ready',
          body: payoutRef ? `Reference: ${payoutRef}` : 'Your reward claim has been approved.',
          refType: 'REWARD_CLAIM',
          refId: id,
        })
      }
      return result
    })
    res.json(updated)
  } catch (err) { next(err) }
})

// ── NeedHub Plus: reward offer catalog (admin-configurable) ────────────────

// A negative pointsCost (or the other numeric fields below) flips the
// reward's own math backwards: claiming it would ADD points/payouts instead
// of spending them, with no limit — a single typo turning a reward into an
// unlimited faucet. maxRedemptions alone legitimately allows -1 (unlimited).
function validateRewardOfferNumbers(body: {
  minVerifiedPoints?: number; pointsCost?: number; rewardValuePaise?: number; maxRedemptions?: number
}): string | null {
  if (body.minVerifiedPoints !== undefined && (!Number.isFinite(body.minVerifiedPoints) || body.minVerifiedPoints < 0)) {
    return 'minVerifiedPoints must be a non-negative number'
  }
  if (body.pointsCost !== undefined && (!Number.isFinite(body.pointsCost) || body.pointsCost < 0)) {
    return 'pointsCost must be a non-negative number'
  }
  if (body.rewardValuePaise !== undefined && (!Number.isFinite(body.rewardValuePaise) || body.rewardValuePaise < 0)) {
    return 'rewardValuePaise must be a non-negative number'
  }
  if (body.maxRedemptions !== undefined && (!Number.isFinite(body.maxRedemptions) || body.maxRedemptions < -1)) {
    return 'maxRedemptions must be -1 (unlimited) or a non-negative number'
  }
  return null
}

adminRouter.get('/reward-offers', async (_req, res) => {
  const offers = await prisma.rewardOffer.findMany({ orderBy: { createdAt: 'asc' } })
  res.json(offers)
})

adminRouter.post('/reward-offers', async (req, res, next) => {
  const body = req.body as {
    key?: string; kind?: string; title?: string; description?: string
    minVerifiedPoints?: number; pointsCost?: number; rewardValuePaise?: number
    maxRedemptions?: number; payoutFieldsJson?: unknown
  }
  if (!body.key || !body.title || !body.description) {
    return next(badRequest('key, title and description are required', 'INVALID_BODY'))
  }
  const numError = validateRewardOfferNumbers(body)
  if (numError) return next(badRequest(numError, 'INVALID_BODY'))
  try {
    const offer = await prisma.rewardOffer.create({
      data: {
        key: body.key,
        kind: (body.kind as any) ?? 'CASHBACK',
        title: body.title,
        description: body.description,
        minVerifiedPoints: body.minVerifiedPoints ?? 1000,
        pointsCost: body.pointsCost ?? 1000,
        rewardValuePaise: body.rewardValuePaise ?? 15000,
        maxRedemptions: body.maxRedemptions ?? -1,
        payoutFieldsJson: (body.payoutFieldsJson as any) ?? null,
      },
    })
    res.status(201).json(offer)
  } catch (err) { next(err) }
})

adminRouter.patch('/reward-offers/:id', async (req, res, next) => {
  const { id } = req.params
  const body = req.body as {
    enabled?: boolean; title?: string; description?: string
    minVerifiedPoints?: number; pointsCost?: number; rewardValuePaise?: number
    maxRedemptions?: number; startsAt?: string; endsAt?: string
  }
  const numError = validateRewardOfferNumbers(body)
  if (numError) return next(badRequest(numError, 'INVALID_BODY'))
  try {
    const offer = await prisma.rewardOffer.update({
      where: { id },
      data: {
        ...(body.enabled !== undefined && { enabled: body.enabled }),
        ...(body.title !== undefined && { title: body.title }),
        ...(body.description !== undefined && { description: body.description }),
        ...(body.minVerifiedPoints !== undefined && { minVerifiedPoints: body.minVerifiedPoints }),
        ...(body.pointsCost !== undefined && { pointsCost: body.pointsCost }),
        ...(body.rewardValuePaise !== undefined && { rewardValuePaise: body.rewardValuePaise }),
        ...(body.maxRedemptions !== undefined && { maxRedemptions: body.maxRedemptions }),
        ...(body.startsAt !== undefined && { startsAt: body.startsAt ? new Date(body.startsAt) : null }),
        ...(body.endsAt !== undefined && { endsAt: body.endsAt ? new Date(body.endsAt) : null }),
      },
    })
    res.json(offer)
  } catch (err) { next(err) }
})

// ── NeedHub Plus: subscription payments ─────────────────────────────────────

adminRouter.get('/plus-payments', async (req, res) => {
  const status = req.query.status as string | undefined
  const payments = await prisma.plusPayment.findMany({
    where: status ? { status: status as any } : undefined,
    orderBy: { createdAt: 'desc' },
    take: 100,
    include: { user: { select: { id: true, displayName: true, email: true } } },
  })
  res.json(payments)
})

adminRouter.patch('/plus-payments/:id', async (req, res, next) => {
  const { id } = req.params
  const { status, adminNotes } = req.body as { status?: string; adminNotes?: string }
  try {
    const payment = await prisma.plusPayment.findUnique({ where: { id } })
    if (!payment) return next(notFound('Payment not found', 'PAYMENT_NOT_FOUND'))

    // Marking PAID activates the subscription via the same compare-and-swap
    // used by the user's own self-report confirm — an admin re-confirming
    // an already-active payment is a safe no-op, never a double credit.
    if (status === 'PAID') {
      await prisma.$transaction(async (tx) => {
        if (adminNotes !== undefined) {
          await tx.plusPayment.update({ where: { id }, data: { adminNotes } })
        }
        await activatePlus(tx, { userId: payment.userId, paymentId: id })
      })
      const fresh = await prisma.plusPayment.findUnique({ where: { id } })
      return res.json(fresh)
    }

    const updated = await prisma.plusPayment.update({
      where: { id },
      data: {
        ...(status ? { status: status as any } : {}),
        ...(adminNotes !== undefined ? { adminNotes } : {}),
      },
    })
    res.json(updated)
  } catch (err) { next(err) }
})
