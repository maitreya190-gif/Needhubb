/**
 * NeedHub Plus's visibility perk: a MODERATE ranking signal for Needs, and a
 * moderate roster tier for ChitChat. Both are deliberately weaker than the
 * existing paid VisibilityBoost (lib/visibility-boost.ts) — a subscription
 * is a recurring, low-effort perk; a paid boost is a one-off purchase that
 * stays the decisive "pin to the top". Premium must never be able to
 * outrank strong organic relevance, Trust Score, or Urgency Mode — see the
 * worked comparisons below and the exhaustive sweep in
 * modules/needs/__tests__/plusRanking.test.ts.
 */

import { prisma } from './prisma'
import { fetchPlusUserIds } from './plus'

// ── Need visibility (feed ranking) ────────────────────────────────────────

/**
 * Added on top of scoreNeed's normal ~0-1 scale, alongside (not instead of)
 * boostBonus. Chosen against every other constant already in the ranking
 * system so the ordering is provable, not just asserted:
 *   - 0.12 < 0.22 (URGENCY_MAX_BOOST, lib/urgency.ts) — money can never
 *     outweigh a verified genuine emergency.
 *   - 0.12 < 0.15 (freshness weight — the smallest single organic weight)
 *     — premium is worth less than simply being newly posted.
 *   - 0.12 ≪ 2.0 (NEED_BOOST_RANK_BONUS) — a paid points-boost stays the
 *     decisive pin-to-top; premium is not that.
 *   - In EARN embeddings mode (semantic weight 0.60): 0.12 / 0.60 = 0.20 of
 *     semanticScore, i.e. 0.40 of raw cosine similarity — premium can only
 *     reorder among needs already comparably relevant to the viewer, never
 *     cross a real relevance gap.
 *   - For CONNECT (trust weight 0.20): a max-trust non-premium poster still
 *     outranks a zero-trust premium one (0.20 > 0.12).
 */
export const PLUS_NEED_RANK_BONUS = 0.12

/**
 * Independent, tighter budget than the paid boost's (max 6) — premium is
 * recurring and potentially widespread across many posters at once, while a
 * paid boost is a one-off purchase, so its ceiling on any one page must be
 * lower.
 */
export const PLUS_VISIBILITY_CAP_RATIO = 0.2
export const PLUS_VISIBILITY_CAP_MIN = 2
export const PLUS_VISIBILITY_CAP_MAX = 4

export function plusVisibilityCap(pageSize: number): number {
  return Math.max(
    PLUS_VISIBILITY_CAP_MIN,
    Math.min(PLUS_VISIBILITY_CAP_MAX, Math.ceil(pageSize * PLUS_VISIBILITY_CAP_RATIO)),
  )
}

/**
 * Which of these need ids may keep their premium bonus on this page. Unlike
 * selectBoostedWithinCap (which sorts by boost value — useless here since
 * PLUS_NEED_RANK_BONUS is flat, so every premium need would tie), this
 * selects by ORGANIC score: the scarce premium slots go to the premium
 * needs that are already most relevant on the page, reinforcing
 * relevance-primacy instead of competing with it.
 */
export function selectPlusWithinCap(
  items: { id: string; plusBonus: number; organicScore: number }[],
  cap: number,
): Set<string> {
  const eligible = items.filter((i) => i.plusBonus > 0).sort((a, b) => b.organicScore - a.organicScore)
  return new Set(eligible.slice(0, cap).map((i) => i.id))
}

/**
 * Which of these need-poster ids currently hold an active Plus subscription.
 * Thin alias over lib/plus.ts's generic fetchPlusUserIds so call sites here
 * read as "poster ids for ranking" rather than a generic user lookup.
 */
export const fetchPlusPosterIds = fetchPlusUserIds

// ── ChitChat visibility (roster ranking) ──────────────────────────────────

/**
 * Only the nearest PLUS_CHITCHAT_TIER_CAP premium users on a roster hold the
 * premium tier — everyone else falls to the normal tier. Premium nudges
 * placement; it cannot colonise the whole roster.
 */
export const PLUS_CHITCHAT_TIER_CAP = 3

/**
 * 2 = active paid VisibilityBoost (unchanged, still decisive), 1 = NeedHub
 * Plus (moderate), 0 = neither. A single, UNCONDITIONAL comparator — the
 * existing code only re-sorts boosted-first `if (activeBoosts.size > 0)`,
 * which would silently drop premium ordering whenever nobody on the roster
 * holds a paid boost (the common case). See chitchat.router.ts for the
 * degenerate-case proof that replacing both existing sorts with this is safe.
 */
export function chitchatTier(userId: string, boosted: Set<string>, plusNearest: Set<string>): 0 | 1 | 2 {
  if (boosted.has(userId)) return 2
  if (plusNearest.has(userId)) return 1
  return 0
}

/**
 * Given a nearest-first-ordered list of userIds, returns the nearest
 * PLUS_CHITCHAT_TIER_CAP of them that hold an active Plus subscription.
 * Fails safe to an empty Set on any DB error, same convention as every
 * other active-boost fetcher.
 */
export async function fetchPlusChitchatTier(orderedUserIds: string[]): Promise<Set<string>> {
  if (orderedUserIds.length === 0) return new Set()
  try {
    const rows = await prisma.plusSubscription.findMany({
      where: {
        userId: { in: orderedUserIds },
        status: 'ACTIVE',
        currentPeriodEnd: { gt: new Date() },
      },
      select: { userId: true },
    })
    const activeSet = new Set(rows.map((r) => r.userId))
    const nearestFirst = orderedUserIds.filter((id) => activeSet.has(id))
    return new Set(nearestFirst.slice(0, PLUS_CHITCHAT_TIER_CAP))
  } catch (err) {
    console.error('[plus-visibility] failed to fetch plus chitchat tier', err)
    return new Set()
  }
}
