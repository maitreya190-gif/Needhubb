/**
 * Paid visibility boosts — spend Impact Points on real, working visibility
 * for a Need or for your Chit-Chat availability. Built on the existing
 * VisibilityBoost model (already had targetType NEED and PROFILE in the
 * schema, but neither was ever read anywhere before this) and the existing
 * PointsLedger for the spend — no new tables, no duplicated point logic.
 *
 * This module owns only the *reading* side (what an active boost is worth
 * in ranking, and how many needs may keep it on one page) plus the
 * chit-chat tier table. Need-boost purchasing itself already existed and is
 * untouched — see POST /needs/:id/boost in needs.router.ts. Chit-chat
 * purchasing is new — see POST /chitchat/boost in chitchat.router.ts.
 */

import { prisma } from './prisma'

// ── Need visibility boost (feed ranking) ─────────────────────────────────

/**
 * Added on top of scoreNeed's normal ~0-1 scale. Deliberately large enough
 * to reliably outrank organic results — a paid boost is a decisive "pin to
 * the top" the way the redeem screen already promises, not a soft nudge
 * like Urgency Mode's AI-evaluated signal. Purchasing itself is already
 * rate-limited by cost (real Impact Points) and by one-boost-per-need at a
 * time (see the existing ALREADY_BOOSTED check in needs.router.ts).
 */
export const NEED_BOOST_RANK_BONUS = 2.0

/**
 * Independent budget from Urgency Mode's visibility cap — the two signals
 * must not be able to crowd each other out of the same page. Same shape
 * (ratio of page size, clamped to a sane min/max) as urgencyVisibilityCap
 * in lib/urgency.ts, so a paid boost can dominate at most a small, bounded
 * slice of any single feed page even if many needs are boosted at once.
 */
export const BOOST_VISIBILITY_CAP_RATIO = 0.2
export const BOOST_VISIBILITY_CAP_MIN = 2
export const BOOST_VISIBILITY_CAP_MAX = 6

export function boostVisibilityCap(pageSize: number): number {
  return Math.max(
    BOOST_VISIBILITY_CAP_MIN,
    Math.min(BOOST_VISIBILITY_CAP_MAX, Math.ceil(pageSize * BOOST_VISIBILITY_CAP_RATIO)),
  )
}

/** Which of these need ids currently have an active (unexpired) boost. */
export async function fetchActiveNeedBoosts(needIds: string[]): Promise<Set<string>> {
  if (needIds.length === 0) return new Set()
  try {
    const rows = await prisma.visibilityBoost.findMany({
      where: { targetType: 'NEED', targetId: { in: needIds }, expiresAt: { gt: new Date() } },
      select: { targetId: true },
    })
    return new Set(rows.map((r) => r.targetId))
  } catch (err) {
    console.error('[visibility-boost] failed to fetch active need boosts', err)
    return new Set()
  }
}

// ── Chit-Chat visibility boost ────────────────────────────────────────────

/**
 * Tiers capped at 12h — chit-chat availability itself maxes out at 12h
 * (see availabilityBody in chitchat.router.ts), so a boost can never outlive
 * the thing it boosts. Costs are lower than a need boost's: a need boost
 * competes for one-time discovery of a specific post, while a chit-chat
 * boost just reorders an already-small, already-nearby roster — a cheaper,
 * lower-stakes signal gets a cheaper price.
 */
export const CHITCHAT_BOOST_TIERS: Record<string, { hours: number; cost: number }> = {
  '3h':  { hours: 3,  cost: 40 },
  '6h':  { hours: 6,  cost: 70 },
  '12h': { hours: 12, cost: 120 },
}

/** Which of these user ids currently have an active Chit-Chat boost. */
export async function fetchActiveChitchatBoosts(userIds: string[]): Promise<Set<string>> {
  if (userIds.length === 0) return new Set()
  try {
    const rows = await prisma.visibilityBoost.findMany({
      where: { targetType: 'PROFILE', targetId: { in: userIds }, expiresAt: { gt: new Date() } },
      select: { targetId: true },
    })
    return new Set(rows.map((r) => r.targetId))
  } catch (err) {
    console.error('[visibility-boost] failed to fetch active chitchat boosts', err)
    return new Set()
  }
}
