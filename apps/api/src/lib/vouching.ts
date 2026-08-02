/**
 * Skill Vouching — an optional, additive endorsement system.
 *
 * A vouch is one user endorsing a specific skill listed on another user's
 * profile, optionally with a testimonial. Nothing about this file changes
 * how anything worked before it existed: no vouches means every function
 * here is simply never called, and the endpoints in modules/vouches are the
 * only way a Vouch row is ever created.
 *
 * Two internal-only values live behind this module and must never reach a
 * client response: `Vouch.credibilityWeight` and `Vouch.suspicious`. Users
 * see whether a vouch is "Verified" (backed by a real completed Need) and
 * the testimonial text — nothing about how much internal weight it carries
 * or whether it was flagged as a suspicious pattern.
 *
 * Visibility integration (requirement 7) is deliberately NOT a second,
 * separate ranking term in scoreNeed. Validated skill endorsements feed
 * Trust Score (see trust-score.ts), and Trust Score already factors into
 * CONNECT ranking at a fixed 20% weight. Routing it through the one existing
 * channel — rather than stacking a second independent boost — is what keeps
 * this "a lightweight signal that complements the pipeline" rather than a
 * second lever that could compound with the first. Badges (an earlier,
 * similar credibility signal) were integrated the same way.
 */

import { prisma } from './prisma'
import { embedBatch, cosineSimilarity, needSignalText, embeddingsAvailable } from './embeddings'
import { computeTrustScore } from './trust-score'
import { fetchTrackRecord, totalFulfilledCount } from './track-record'
import { earnedBadgeCount } from './badges'
import { isBlockedBetween } from '../modules/friends/friends.service'

// ── Tuning constants — the only place these live ────────────────────────────

/** An unverified vouch's credibility never exceeds this fraction, however
 * high the voucher's own trust score is. Trust in the voucher does not
 * manufacture evidence of a real interaction that didn't happen. */
export const VOUCH_UNVERIFIED_TRUST_CAP = 0.4

/** Diminishing per-collaboration bonus for a verified vouch, and the point
 * past which additional collaborations stop adding more. */
export const VOUCH_COLLAB_BONUS_PER = 0.1
export const VOUCH_COLLAB_BONUS_MAX_COUNT = 4

/** A vouch flagged suspicious is crushed toward zero, not deleted or hidden
 * from the count — see detectSuspiciousVouch. Never exactly 0: a small floor
 * avoids a divide-by-zero-shaped edge case elsewhere and keeps the row from
 * having a meaningless, uninspectable weight during internal debugging. */
export const VOUCH_SUSPICIOUS_MULTIPLIER = 0.1

/** A verified interaction (a real completed Need together) makes reciprocal
 * or rapid vouching normal, not suspicious — so these windows only ever
 * apply to unverified vouches. */
export const RECIPROCAL_WINDOW_HOURS = 72
export const RAPID_FIRE_WINDOW_HOURS = 24
export const RAPID_FIRE_MAX_VOUCHES = 5

/** Vouches below this credibility contribute nothing to Trust Score — a
 * vouch can exist (visible, editable) without being trust-eligible. */
export const TRUST_ELIGIBLE_CREDIBILITY_MIN = 0.3

export const MAX_RECENT_VOUCHERS_PER_SKILL = 5

/**
 * Sanity-only floor — rules out a negative/orthogonal cosine, nothing more.
 * Measured against real completed needs, bare skill-label embeddings sit on
 * a much lower absolute scale than need-tagging.ts's curated, hint-enriched
 * vocabulary: a *correct* match ("UI/UX" suggested for a UI-design need)
 * scored 0.173, not the 0.5+ that vocabulary's tags need to clear. A fixed
 * absolute floor tuned to that other scale would silently suggest nothing,
 * ever, here — the exact failure this constant is set low enough to avoid.
 *
 * What still makes this a *ranking*, not noise, is relative order: within
 * one need, the genuinely relevant skill reliably scored well above the
 * others (0.173 vs 0.114/0.045/0.027/0.002). Rather than chase an absolute
 * cutoff from a handful of real samples, this leans on requirement 3
 * instead — the reviewer sees every suggestion and chooses what to actually
 * endorse, so surfacing the best few available and letting a human filter
 * is more robust than a fragile magic number would be.
 */
export const SKILL_SUGGESTION_MIN_SIMILARITY = 0
export const MAX_SUGGESTED_SKILLS = 5

// ── Credibility weighting (pure) ─────────────────────────────────────────────

export interface VouchCredibilityInput {
  voucherTrustScore: number // 0-100
  verified: boolean
  collaborationCount: number
  /** Fraction (0-1) of this voucher's OTHER vouches flagged suspicious —
   * tracks the reliability of their vouching pattern, not just identity. */
  voucherPriorSuspiciousRate: number
  suspicious: boolean
}

/**
 * Internal credibility weight in [0, 1] for one vouch. Never exposed — read
 * only by countTrustEligibleVouches (Trust Score) and nothing else.
 */
export function computeVouchCredibility(input: VouchCredibilityInput): number {
  const trustFactor = clamp01(input.voucherTrustScore / 100)

  let base: number
  if (input.verified) {
    // A real completed collaboration is the strongest signal available that
    // this endorsement is grounded in something that actually happened.
    // Trust still matters — a low-trust voucher's verified vouch counts for
    // less than an established user's — but the verified interaction itself
    // carries at least as much weight as identity does.
    const collabBonus = Math.min(input.collaborationCount, VOUCH_COLLAB_BONUS_MAX_COUNT) * VOUCH_COLLAB_BONUS_PER
    base = clamp01(0.6 + collabBonus) * 0.5 + trustFactor * 0.5
  } else {
    // No verified interaction: a stranger's opinion, capped low regardless
    // of the voucher's own standing.
    base = trustFactor * VOUCH_UNVERIFIED_TRUST_CAP
  }

  base *= clamp01(1 - input.voucherPriorSuspiciousRate)
  if (input.suspicious) base *= VOUCH_SUSPICIOUS_MULTIPLIER

  return clamp01(base)
}

function clamp01(n: number): number {
  return Math.max(0, Math.min(1, n))
}

// ── Verified-interaction detection (I/O) ────────────────────────────────────

/**
 * Whether voucher and vouchee have completed a Need together — one posted
 * it, the other's response was accepted, and the need reached FULFILLED.
 * Counts distinct needs both ways, since either could have been the poster.
 * Never throws: on any failure this reports no verified interaction, which
 * is the safe default (a vouch just becomes a standard endorsement instead
 * of blocking or erroring).
 */
export async function detectVerifiedInteraction(
  voucherId: string,
  voucheeId: string,
): Promise<{ verified: boolean; collaborationCount: number }> {
  try {
    const completedTogether = await prisma.interestResponse.findMany({
      where: {
        status: 'ACCEPTED',
        OR: [
          { responderId: voucherId, need: { posterId: voucheeId, status: 'FULFILLED' } },
          { responderId: voucheeId, need: { posterId: voucherId, status: 'FULFILLED' } },
        ],
      },
      select: { needId: true },
      distinct: ['needId'],
    })
    return { verified: completedTogether.length > 0, collaborationCount: completedTogether.length }
  } catch (err) {
    console.error('[vouching] failed to detect verified interaction, treating as unverified', voucherId, voucheeId, err)
    return { verified: false, collaborationCount: 0 }
  }
}

// ── Anti-abuse detection (I/O) ───────────────────────────────────────────────

/**
 * Reciprocal or rapid-fire vouching pattern, checked only for unverified
 * vouches — after a genuine shared Need, both people vouching for each other
 * quickly is normal, not abuse. Fails open: a detection error never blocks a
 * legitimate vouch, it just isn't flagged.
 */
export async function detectSuspiciousVouch(
  voucherId: string,
  voucheeId: string,
  verified: boolean,
): Promise<boolean> {
  if (verified) return false
  try {
    const [reciprocal, rapidFireCount] = await Promise.all([
      prisma.vouch.findFirst({
        where: {
          voucherId: voucheeId,
          voucheeId: voucherId,
          verified: false,
          createdAt: { gte: new Date(Date.now() - RECIPROCAL_WINDOW_HOURS * 3_600_000) },
        },
        select: { id: true },
      }),
      prisma.vouch.count({
        where: { voucherId, createdAt: { gte: new Date(Date.now() - RAPID_FIRE_WINDOW_HOURS * 3_600_000) } },
      }),
    ])
    return reciprocal !== null || rapidFireCount >= RAPID_FIRE_MAX_VOUCHES
  } catch (err) {
    console.error('[vouching] suspicious-pattern check failed, not flagging', voucherId, voucheeId, err)
    return false
  }
}

/** Fraction of this voucher's existing vouches already flagged suspicious. */
async function getVoucherSuspiciousRate(voucherId: string): Promise<number> {
  try {
    const [total, suspicious] = await Promise.all([
      prisma.vouch.count({ where: { voucherId } }),
      prisma.vouch.count({ where: { voucherId, suspicious: true } }),
    ])
    return total === 0 ? 0 : suspicious / total
  } catch (err) {
    console.error('[vouching] failed to compute voucher suspicious rate, defaulting to 0', voucherId, err)
    return 0
  }
}

async function computeUserTrustScoreForVouching(userId: string): Promise<number> {
  try {
    const [user, record, eligibleVouchCount] = await Promise.all([
      prisma.user.findUnique({
        where: { id: userId },
        select: { emailVerifiedAt: true, phoneVerifiedAt: true, profile: { select: { faceVerifiedAt: true } } },
      }),
      fetchTrackRecord(userId),
      countTrustEligibleVouches(userId),
    ])
    const verification = {
      emailVerifiedAt: user?.emailVerifiedAt ?? null,
      phoneVerifiedAt: user?.phoneVerifiedAt ?? null,
      faceVerifiedAt: user?.profile?.faceVerifiedAt ?? null,
    }
    const badgeInputs = { ...verification, ...record }
    return computeTrustScore({
      ...verification,
      approvedCertificateCount: record.approvedCertificateCount,
      fulfilledNeedCount: totalFulfilledCount(record),
      avgRating: record.avgRating,
      ratingCount: record.ratingCount,
      earnedBadgeCount: earnedBadgeCount(badgeInputs),
      validatedSkillEndorsementCount: eligibleVouchCount,
    })
  } catch (err) {
    console.error('[vouching] failed to compute voucher trust score, defaulting to 0', userId, err)
    return 0
  }
}

// ── Vouch evaluation (I/O — orchestration) ──────────────────────────────────

export interface VouchEvaluation {
  verified: boolean
  collaborationCount: number
  suspicious: boolean
  credibilityWeight: number
}

/**
 * Everything a new vouch needs computed before it is created. Unlike urgency
 * evaluation, this involves no LLM call — only database reads — so it is
 * fast enough to await directly in the request instead of needing a
 * fire-and-forget follow-up write.
 */
export async function evaluateNewVouch(voucherId: string, voucheeId: string): Promise<VouchEvaluation> {
  const [{ verified, collaborationCount }, priorSuspiciousRate] = await Promise.all([
    detectVerifiedInteraction(voucherId, voucheeId),
    getVoucherSuspiciousRate(voucherId),
  ])
  const [suspicious, voucherTrustScore] = await Promise.all([
    detectSuspiciousVouch(voucherId, voucheeId, verified),
    computeUserTrustScoreForVouching(voucherId),
  ])

  const credibilityWeight = computeVouchCredibility({
    voucherTrustScore,
    verified,
    collaborationCount,
    voucherPriorSuspiciousRate: priorSuspiciousRate,
    suspicious,
  })

  return { verified, collaborationCount, suspicious, credibilityWeight }
}

// ── Trust Score integration ─────────────────────────────────────────────────

/** How many of this user's received vouches are strong enough to count
 * toward Trust Score — see TRUST_ELIGIBLE_CREDIBILITY_MIN and
 * trust-score.ts's `validatedSkillEndorsementCount`. */
export async function countTrustEligibleVouches(voucheeId: string): Promise<number> {
  const counts = await fetchTrustEligibleVouchCounts([voucheeId])
  return counts.get(voucheeId) ?? 0
}

/** Batched form of countTrustEligibleVouches — one grouped query for many
 * users instead of one query per user, for the feed's per-poster trust-score
 * pass (same batching shape as fetchTrackRecords in track-record.ts). */
export async function fetchTrustEligibleVouchCounts(voucheeIds: string[]): Promise<Map<string, number>> {
  const out = new Map<string, number>()
  if (voucheeIds.length === 0) return out
  try {
    const groups = await prisma.vouch.groupBy({
      by: ['voucheeId'],
      where: {
        voucheeId: { in: voucheeIds },
        suspicious: false,
        credibilityWeight: { gte: TRUST_ELIGIBLE_CREDIBILITY_MIN },
      },
      _count: { id: true },
    })
    for (const g of groups) out.set(g.voucheeId, g._count.id)
    return out
  } catch (err) {
    console.error('[vouching] failed to batch-count trust-eligible vouches, defaulting to 0 for all', err)
    return out
  }
}

// ── AI-assisted skill suggestion (I/O) ──────────────────────────────────────

export interface SuggestableSkill {
  id: string
  label: string
}

/**
 * Suggests which of the vouchee's already-declared skills were likely
 * demonstrated on a specific completed Need — assistance only, never an
 * endorsement. The reviewer chooses what to actually vouch for; nothing here
 * writes a Vouch row.
 *
 * Reuses the same embedding infrastructure as need-tagging.ts. Two honest
 * differences from that module: skill labels here are arbitrary and
 * user-entered rather than a fixed ~28-label vocabulary with a hand-written
 * descriptive phrase per label, so bare-label embeddings sit on a lower,
 * noisier absolute scale — measured directly against real completed needs
 * (see SKILL_SUGGESTION_MIN_SIMILARITY). Consequently this ranks candidates
 * rather than gating them on an absolute score: the reviewer sees every
 * suggestion and chooses what to actually vouch for, so a wrong result costs
 * one ignored option, not a bad tag applied to a search result.
 */
export async function suggestSkillsForCompletedNeed(
  need: { title: string; description: string; earnCategory: string | null; connectCategory: string | null },
  candidateSkills: SuggestableSkill[],
): Promise<SuggestableSkill[]> {
  if (candidateSkills.length === 0 || !embeddingsAvailable()) return []
  try {
    const [needVecs, skillVecs] = await Promise.all([
      embedBatch([needSignalText(need)], 'search_document'),
      embedBatch(candidateSkills.map((s) => s.label), 'search_document'),
    ])
    if (!needVecs?.[0] || !skillVecs) return []

    const scored = candidateSkills
      .map((skill, i) => ({ skill, score: cosineSimilarity(needVecs[0], skillVecs[i]) }))
      .filter((s) => s.score >= SKILL_SUGGESTION_MIN_SIMILARITY)
      .sort((a, b) => b.score - a.score)

    return scored.slice(0, MAX_SUGGESTED_SKILLS).map((s) => s.skill)
  } catch (err) {
    console.error('[vouching] skill suggestion failed, returning none', err)
    return []
  }
}

// ── Profile display (I/O) ───────────────────────────────────────────────────

export interface SkillVouchDisplay {
  skillId: string
  label: string
  vouchCount: number
  verifiedVouchCount: number
  recentVouchers: {
    voucherId: string
    voucherName: string
    verified: boolean
    testimonial: string | null
    createdAt: Date
  }[]
}

/**
 * Per-skill vouch summaries for a profile view. Suspicious vouches never
 * surface here — silently excluded, per requirement 8, same as they are
 * excluded from Trust Score. Vouches from anyone the viewer has blocked (in
 * either direction) are also excluded — the one existing privacy mechanism
 * this reuses rather than inventing a new settings field for "privacy
 * settings" the app does not otherwise have.
 */
export async function fetchSkillVouchSummaries(
  voucheeId: string,
  skillIds: string[],
  viewerId: string | null,
): Promise<Map<string, SkillVouchDisplay>> {
  const out = new Map<string, SkillVouchDisplay>()
  if (skillIds.length === 0) return out
  try {
    const vouches = await prisma.vouch.findMany({
      where: { voucheeId, skillId: { in: skillIds }, suspicious: false },
      include: { voucher: { select: { id: true, displayName: true } }, skill: { select: { label: true } } },
      orderBy: { createdAt: 'desc' },
    })
    if (vouches.length === 0) return out

    let visible = vouches
    if (viewerId) {
      const voucherIds = Array.from(new Set(vouches.map((v) => v.voucherId)))
      const blockedFlags = await Promise.all(
        voucherIds.map(async (id) => [id, await isBlockedBetween(viewerId, id)] as const),
      )
      const blockedIds = new Set(blockedFlags.filter(([, blocked]) => blocked).map(([id]) => id))
      visible = vouches.filter((v) => !blockedIds.has(v.voucherId))
    }

    for (const skillId of skillIds) {
      const forSkill = visible.filter((v) => v.skillId === skillId)
      if (forSkill.length === 0) continue
      out.set(skillId, {
        skillId,
        label: forSkill[0].skill.label,
        vouchCount: forSkill.length,
        verifiedVouchCount: forSkill.filter((v) => v.verified).length,
        recentVouchers: forSkill.slice(0, MAX_RECENT_VOUCHERS_PER_SKILL).map((v) => ({
          voucherId: v.voucher.id,
          voucherName: v.voucher.displayName,
          verified: v.verified,
          testimonial: v.testimonial,
          createdAt: v.createdAt,
        })),
      })
    }
    return out
  } catch (err) {
    console.error('[vouching] failed to fetch vouch summaries, showing none', voucheeId, err)
    return out
  }
}

// ── Response hygiene ─────────────────────────────────────────────────────────

/**
 * Strip `credibilityWeight` and `suspicious` from a Vouch (or any object
 * shaped like one) before it is ever returned to a client. Same rationale as
 * stripInternalUrgencyFields — this codebase returns raw Prisma rows
 * directly with no field allowlist, so a new column is otherwise serialized
 * automatically the moment it exists.
 */
export function stripInternalVouchFields<T extends { credibilityWeight?: unknown; suspicious?: unknown }>(
  vouch: T,
): Omit<T, 'credibilityWeight' | 'suspicious'> {
  const { credibilityWeight: _a, suspicious: _b, ...rest } = vouch
  return rest
}

/** Best-effort viewer identity from a request that may or may not be
 * authenticated — mirrors the identical helper in needs.router.ts, kept as
 * its own small copy here rather than importing across modules, so this
 * feature stays isolated per the "modular" requirement. */
export function tryGetUserId(req: unknown): string | null {
  try {
    const auth = (req as { headers?: Record<string, string> }).headers?.authorization
    if (!auth?.startsWith('Bearer ')) return null
    const [, payload] = auth.slice(7).split('.')
    if (!payload) return null
    const decoded = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'))
    return typeof decoded.sub === 'string' ? decoded.sub : null
  } catch { return null }
}
