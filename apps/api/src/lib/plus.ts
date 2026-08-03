/**
 * NeedHub Plus subscription lifecycle. No cron exists in this stack, so
 * expiry follows the same lazy, read-time pattern as Urgency Mode's
 * isExpired/expireIfNeeded (lib/urgency.ts) — a subscription is only ever
 * "active" according to isPlusActive()'s predicate, checked fresh on every
 * read. A missed or delayed write can therefore never leak premium ranking
 * to a lapsed subscriber, and a late write can never wrongly revoke one
 * either — the stored `status` is a hint, the (status, currentPeriodEnd)
 * pair together is the actual truth.
 */

import { prisma } from './prisma'
import type { Prisma, PlusSubscriptionStatus } from '@prisma/client'

export const PLUS_PERIOD_DAYS = 30

type SubscriptionLike = {
  status: PlusSubscriptionStatus
  currentPeriodEnd: Date | null
} | null | undefined

/** Whether a subscription is genuinely active right now — both the stored
 * status AND an unexpired period must hold. Never trust status alone. */
export function isPlusActive(sub: SubscriptionLike, now: Date = new Date()): boolean {
  if (!sub) return false
  if (sub.status !== 'ACTIVE') return false
  if (!sub.currentPeriodEnd) return false
  return sub.currentPeriodEnd.getTime() > now.getTime()
}

/**
 * A self-reported "I paid" claim may only instantly activate Plus when the
 * user does NOT already hold a comfortably-active subscription. Without
 * this, a scripted loop of subscribe -> self-report-confirm -> repeat would
 * stack 30-day periods indefinitely with zero payment ever happening, and
 * no admin would see it until they happened to check the self-reported
 * queue. A legitimate early renewal (paying again a few days before the
 * current period ends) is still allowed through self-report; anything
 * earlier than that must go through admin confirmation instead — see
 * POST /plus/payments/:id/confirm.
 */
export const SELF_REPORT_RENEWAL_WINDOW_MS = 3 * 24 * 3_600_000

export function canSelfReportInstantly(sub: SubscriptionLike, now: Date = new Date()): boolean {
  if (!isPlusActive(sub, now)) return true
  return sub!.currentPeriodEnd!.getTime() - now.getTime() <= SELF_REPORT_RENEWAL_WINDOW_MS
}

/**
 * Best-effort status flip to EXPIRED once the period has passed. Exactly
 * like expireIfNeeded, this is fire-and-forget — isPlusActive()'s read-time
 * predicate is what actually guarantees an expired subscription stops
 * counting anywhere, so a delayed or failed write here degrades nothing
 * user-visible.
 */
export async function expirePlusIfNeeded(sub: {
  userId: string
  status: PlusSubscriptionStatus
  currentPeriodEnd: Date | null
}, now: Date = new Date()): Promise<void> {
  if (sub.status !== 'ACTIVE') return
  if (!sub.currentPeriodEnd || sub.currentPeriodEnd.getTime() > now.getTime()) return
  try {
    await prisma.plusSubscription.updateMany({
      where: { userId: sub.userId, status: 'ACTIVE' },
      data: { status: 'EXPIRED' },
    })
  } catch (err) {
    console.error('[plus] failed to expire subscription', sub.userId, err)
  }
}

/** Which of these user ids currently hold an active NeedHub Plus subscription. */
export async function fetchPlusUserIds(userIds: string[]): Promise<Set<string>> {
  if (userIds.length === 0) return new Set()
  try {
    const rows = await prisma.plusSubscription.findMany({
      where: {
        userId: { in: userIds },
        status: 'ACTIVE',
        currentPeriodEnd: { gt: new Date() },
      },
      select: { userId: true },
    })
    return new Set(rows.map((r) => r.userId))
  } catch (err) {
    console.error('[plus] failed to fetch active plus users', err)
    return new Set()
  }
}

/**
 * Credits a payment and (re)activates the subscription — a compare-and-swap,
 * never a read-then-write. Without the `status: { not: 'PAID' }` guard, an
 * admin double-clicking "Confirm" (or, later, a replayed provider webhook)
 * would grant two extra periods for one payment. If another request already
 * claimed this payment, this is a silent no-op.
 *
 * Must be called inside a transaction the caller owns (mirrors
 * pushNotification's tx-scoped convention).
 */
export async function activatePlus(
  tx: Prisma.TransactionClient,
  args: { userId: string; paymentId: string; providerPaymentId?: string | null; periodDays?: number },
): Promise<{ activated: boolean }> {
  const periodDays = args.periodDays ?? PLUS_PERIOD_DAYS
  const claimed = await tx.plusPayment.updateMany({
    where: { id: args.paymentId, status: { not: 'PAID' } },
    data: {
      status: 'PAID',
      providerPaymentId: args.providerPaymentId ?? undefined,
    },
  })
  if (claimed.count === 0) return { activated: false }

  const now = new Date()
  const existing = await tx.plusSubscription.findUnique({ where: { userId: args.userId } })
  // Renewing before the current period ends stacks on top of it instead of
  // truncating it; renewing after it lapsed (or on first-ever activation)
  // starts a fresh period from now.
  const isStacking = !!existing?.currentPeriodEnd && existing.currentPeriodEnd.getTime() > now.getTime()
  const periodStart = isStacking ? existing!.currentPeriodStart ?? now : now
  const periodEnd = new Date((isStacking ? existing!.currentPeriodEnd! : now).getTime() + periodDays * 24 * 3_600_000)

  await tx.plusSubscription.upsert({
    where: { userId: args.userId },
    update: {
      status: 'ACTIVE',
      currentPeriodStart: periodStart,
      currentPeriodEnd: periodEnd,
      cancelAtPeriodEnd: false,
    },
    create: {
      userId: args.userId,
      status: 'ACTIVE',
      currentPeriodStart: periodStart,
      currentPeriodEnd: periodEnd,
    },
  })
  await tx.plusPayment.update({
    where: { id: args.paymentId },
    data: { periodStart, periodEnd },
  })

  return { activated: true }
}
