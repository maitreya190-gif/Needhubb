/**
 * Urgency Mode — an optional, additive visibility signal.
 *
 * Off by default. A need with `isUrgent = false` (every need created before
 * this shipped, and every need created after it unless the poster opts in)
 * is completely untouched by anything in this file: every function here
 * returns a no-op contribution (0 boost, stage 0, unchanged score) for a
 * non-urgent need. This file adds a signal on top of the existing ranking
 * pipeline; it does not replace or rebalance any of it.
 *
 * Three internal-only values live behind this module and must never reach a
 * client response or a UI: `Need.urgencyConfidence`, the computed rescue
 * stage, and `UrgencyProfile` (a user's private urgency track record, kept
 * deliberately separate from the public Trust Score in trust-score.ts). The
 * user only ever knows whether they turned Urgency Mode on — never how it
 * was judged.
 *
 * "Continuous learning" here is honest about what it actually is: there is no
 * training pipeline in this codebase, so evaluation improves the same way the
 * rest of this app's heuristics do — by feeding recorded outcomes (fulfilled
 * before deadline vs. expired with no engagement) into the next evaluation's
 * inputs via UrgencyProfile.reliability. It is a feedback loop over stored
 * history, not model retraining.
 */

import type { EarnCategory, ConnectCategory } from '@prisma/client'
import { prisma } from './prisma'
import { config } from '../config'
import { computeTrustScore } from './trust-score'
import { fetchTrackRecord, totalFulfilledCount } from './track-record'
import { computeBadges, earnedBadgeCount } from './badges'
import { countTrustEligibleVouches } from './vouching'

// ── Tuning constants — the only place these live ────────────────────────────

/** Hours before deadline over which the visibility boost ramps from 0 to max. */
export const URGENCY_RAMP_HOURS = 72

/**
 * Ceiling on the urgency boost added to a need's rank score. The live scoring
 * function's weighted components already sum to ~1.0 (see scoreNeed in
 * needs.router.ts); capping the addition well below that keeps relevance,
 * proximity and trust dominant, exactly as required — urgency nudges the
 * order, it does not override it.
 */
export const URGENCY_MAX_BOOST = 0.22

/** Extra fixed nudge applied only at Rescue Mode's final stage. Small and
 * bounded on purpose — see computeRescueStage. */
export const RESCUE_STAGE3_BONUS = 0.05

/** Below this confidence, a need is excluded from Rescue Mode. Rescue
 * expands visibility for needs the AI believes are genuinely urgent; it must
 * not become a reward for urgency claims flagged as weak. */
export const RESCUE_MIN_CONFIDENCE = 0.35

/** Distance-cutoff multiplier per rescue stage — how far past the viewer's
 * chosen radius a rescued need is still allowed to surface. */
export const RESCUE_DISTANCE_MULTIPLIER: Record<0 | 1 | 2 | 3, number> = {
  0: 1, 1: 1, 2: 1.5, 3: 2,
}

/** Hours-remaining threshold to enter each rescue stage, given ~zero
 * engagement. Stage 1 starts a day out; stage 3 is the final hours. */
const RESCUE_STAGE_HOURS: Record<1 | 2 | 3, number> = { 1: 24, 2: 12, 3: 4 }

/** Reliability nudges, clamped into [0, 1]. Deliberately asymmetric — misuse
 * costs more than a single justified outcome earns, so reliability tracks
 * genuine pattern, not one lucky evaluation. */
const RELIABILITY_NUDGE_UP = 0.05
const RELIABILITY_NUDGE_DOWN = 0.08
const RELIABILITY_NEUTRAL = 0.5

/**
 * Renewal-abuse guard: each renewal of the same need multiplies the final
 * confidence by this much less, so repeatedly renewing cannot keep earning
 * the same boost forever. Never fully zeroed — RENEWAL_DAMPENING_FLOOR keeps
 * a small amount of headroom, because a need can legitimately still be
 * urgent on its third renewal; it just cannot coast on the same evaluation
 * it got the first time.
 */
export const RENEWAL_DAMPENING_PER_GENERATION = 0.15
export const RENEWAL_DAMPENING_FLOOR = 0.3

/** Multiplicative discount applied to confidence for a need at this renewal
 * generation. Generation 0 (never renewed) returns 1 — no discount. */
export function renewalDampeningFactor(renewalGeneration: number): number {
  return Math.max(
    RENEWAL_DAMPENING_FLOOR,
    1 - Math.max(0, renewalGeneration) * RENEWAL_DAMPENING_PER_GENERATION,
  )
}

// ── Visibility cap ───────────────────────────────────────────────────────────

/**
 * Bounds how many needs on one page can hold their urgency boost, so urgent
 * posts nudge the order without ever being able to dominate a feed page or
 * degrade its quality. Configurable via the three constants below rather
 * than hardcoded inline, so the balance can be tuned without touching logic.
 */
export const URGENT_VISIBILITY_CAP_RATIO = 0.2
export const URGENT_VISIBILITY_CAP_MIN = 3
export const URGENT_VISIBILITY_CAP_MAX = 8

/** How many needs on a page of this size may keep their urgency boost. */
export function urgencyVisibilityCap(pageSize: number): number {
  return Math.max(
    URGENT_VISIBILITY_CAP_MIN,
    Math.min(URGENT_VISIBILITY_CAP_MAX, Math.ceil(pageSize * URGENT_VISIBILITY_CAP_RATIO)),
  )
}

/**
 * Given every need's id and how much urgency contributed to its score,
 * returns the ids allowed to keep that contribution — the top `cap` by
 * contribution size. Everything else is NOT penalized (see requirement 4):
 * the caller subtracts exactly the boost back out, returning those needs to
 * precisely the score they would have had had they never opted into urgency
 * at all. They stay fully visible in the feed, just without extra help
 * climbing further once the cap is full.
 */
export function selectBoostedWithinCap(
  items: { id: string; boost: number }[],
  cap: number,
): Set<string> {
  const boosted = items.filter((i) => i.boost > 0).sort((a, b) => b.boost - a.boost)
  return new Set(boosted.slice(0, cap).map((i) => i.id))
}

// ── AI evaluation ────────────────────────────────────────────────────────────

export interface UrgencyEvalInput {
  title: string
  description: string
  category: string // earnCategory or connectCategory label
  deadline: Date
  createdAt: Date
  trustScore: number // 0-100, see trust-score.ts
  reliability: number // 0-1, this poster's UrgencyProfile.reliability (0.5 if new)
  /**
   * Rough local supply/demand pressure in [0, 1] — how many open needs are
   * already competing for help in this category versus how much responder
   * activity exists for it. 0.5 when unknown. This is intentionally a coarse
   * approximation (see marketPressure below), not a precise market model.
   */
  marketPressure: number
  /** 0 for an original need; N+1 for a need renewed from generation N. */
  renewalGeneration: number
}

export interface UrgencyEvalResult {
  confidence: number
  /** Short natural-language summary of the AI's reasoning, including its
   * delay-cost read — stored only in UrgencyEvaluationLog, never surfaced. */
  reasoning: string | null
  usedLlm: boolean
}

const SYSTEM_PROMPT = `You are an urgency-justification evaluator for NeedHub.

A user has marked a request as URGENT with a specific deadline. Judge how
justified that urgency actually is, from the text alone — the timeframe, the
nature of the task, and whether the language matches genuine time pressure
versus an attempt to game visibility.

Weigh delay cost explicitly: would the real-world value of fulfilling this
request drop significantly if it were delayed by even a few hours — e.g. "need
a ride to catch my flight in 2 hours", "need a proofreader before my 5pm
submission"? That is genuinely high-urgency. Contrast with a request that
stays just as useful later despite carrying a deadline — e.g. "need a tutor
sometime this week, urgent!" — which should score lower even with a similar
stated timeframe, because delaying it costs little.

Return STRICT JSON: { "confidence": number, "reasoning": string } where
confidence is in [0, 1] and reasoning is one short sentence explaining the
judgment, including the delay-cost read. 0 = not justified (vague, no real
time pressure, low delay cost, or deadline implausible for the task). 1 =
clearly and specifically time-critical with high delay cost.
Be balanced: most genuine urgent requests should land between 0.4 and 0.8.
Reserve extremes for clear cases. Return ONLY the JSON object.`

/**
 * Silent server-side judgment of how justified a need's urgency claim is.
 * Blends an LLM read of the text (including an explicit delay-cost read —
 * see the prompt) with cheap structural heuristics (deadline plausibility,
 * poster trust, this poster's urgency track record, local pressure), then
 * applies a renewal-abuse discount. Never throws — on any failure this falls
 * back to the heuristic half alone, because urgency evaluation is an
 * enhancement to a need that already exists; it must never be able to block
 * or fail need creation.
 */
export async function evaluateUrgency(input: UrgencyEvalInput): Promise<UrgencyEvalResult> {
  const heuristic = heuristicUrgencyScore(input)
  const llm = await tryLlmUrgencyScore(input)
  // LLM reads the text; heuristics ground it in this user's actual history.
  // Heuristic keeps a majority say so a well-written but ungrounded claim
  // from a low-reliability poster can't fully override their track record.
  const blended = llm == null ? heuristic : clamp01(0.45 * llm.confidence + 0.55 * heuristic)
  const dampened = clamp01(blended * renewalDampeningFactor(input.renewalGeneration))
  return { confidence: dampened, reasoning: llm?.reasoning ?? null, usedLlm: llm != null }
}

/**
 * Honest limitation: this cannot actually assess delay cost — "does the
 * value of this request drop if delayed" is a reading-comprehension judgment
 * only the LLM half can make (see the prompt). Deadline plausibility is the
 * closest structural proxy available when the LLM is unavailable, which is
 * why heuristic-only mode leans on it more heavily than the blended score
 * does.
 */
function heuristicUrgencyScore(input: UrgencyEvalInput): number {
  const hoursToDeadline = (input.deadline.getTime() - input.createdAt.getTime()) / 3_600_000
  // A deadline that's implausibly soon (minutes away) or very far out (weeks)
  // both read as less genuinely "urgent" than a same-day-to-few-days window.
  // Peaks around 12-48h, decays on either side.
  const deadlinePlausibility =
    hoursToDeadline <= 0 ? 0
    : hoursToDeadline <= 48 ? clamp01(hoursToDeadline / 24)
    : clamp01(1 - (hoursToDeadline - 48) / (24 * 12))

  const trustFactor = clamp01(input.trustScore / 100)
  const reliabilityFactor = input.reliability
  const pressureFactor = clamp01(input.marketPressure)

  // Deadline shape carries the most weight — it's the one directly-checkable
  // fact. Track record and trust temper it; market pressure is a minor tilt.
  return clamp01(
    0.40 * deadlinePlausibility +
    0.25 * reliabilityFactor +
    0.20 * trustFactor +
    0.15 * pressureFactor,
  )
}

async function tryLlmUrgencyScore(
  input: UrgencyEvalInput,
): Promise<{ confidence: number; reasoning: string | null } | null> {
  const baseUrl = process.env.LLM_BASE_URL
  const key = config.llmApiKey
  const model = config.llmModel
  if (!baseUrl || !key || !model) return null

  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), 12000)
  try {
    const res = await fetch(`${baseUrl}/chat/completions`, {
      method: 'POST',
      signal: controller.signal,
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model,
        response_format: { type: 'json_object' },
        temperature: 0.2,
        messages: [
          { role: 'system', content: SYSTEM_PROMPT },
          {
            role: 'user',
            content: [
              `Title: ${input.title}`,
              `Description: ${input.description}`,
              `Category: ${input.category}`,
              `Deadline: ${input.deadline.toISOString()}`,
              `Posted at: ${input.createdAt.toISOString()}`,
            ].join('\n').slice(0, 2000),
          },
        ],
      }),
    })
    if (!res.ok) return null
    const data = (await res.json()) as { choices?: { message?: { content?: string } }[] }
    const raw = data.choices?.[0]?.message?.content?.trim()
    if (!raw) return null
    const stripped = raw.replace(/^```(?:json)?\s*|\s*```$/g, '')
    const parsed = JSON.parse(stripped) as { confidence?: unknown; reasoning?: unknown }
    if (typeof parsed.confidence !== 'number' || Number.isNaN(parsed.confidence)) return null
    return {
      confidence: clamp01(parsed.confidence),
      reasoning: typeof parsed.reasoning === 'string' ? parsed.reasoning.slice(0, 500) : null,
    }
  } catch (err) {
    console.error('[urgency] LLM evaluation unavailable, using heuristic only', err)
    return null
  } finally {
    clearTimeout(timeout)
  }
}

/**
 * Coarse local supply/demand pressure for a category: how many other OPEN
 * needs are already competing for help there, relative to how many distinct
 * people have recently responded to anything in it. Deliberately cheap —
 * category-scoped counts, not a geo query — this is one signal among several,
 * not a precision market model. Returns 0.5 (neutral) on any failure.
 */
export async function marketPressure(
  needType: 'EARN' | 'CONNECT',
  earnCategory: EarnCategory | null,
  connectCategory: ConnectCategory | null,
): Promise<number> {
  try {
    const since = new Date(Date.now() - 14 * 24 * 3_600_000)
    const [openCount, responderCount] = await Promise.all([
      prisma.need.count({
        where:
          needType === 'EARN'
            ? { needType, earnCategory, status: 'OPEN' }
            : { needType, connectCategory, status: 'OPEN' },
      }),
      prisma.interestResponse.count({
        where: {
          need:
            needType === 'EARN' ? { needType, earnCategory } : { needType, connectCategory },
          createdAt: { gte: since },
        },
      }),
    ])
    if (openCount === 0) return 0.5
    // More open demand per responder => more pressure => higher score.
    return clamp01(openCount / (openCount + responderCount + 1))
  } catch (err) {
    console.error('[urgency] market pressure unavailable, using neutral', err)
    return 0.5
  }
}

// ── Ranking contribution (pure — no I/O) ────────────────────────────────────

export interface UrgencyRankInput {
  isUrgent: boolean
  urgencyConfidence: number | null
  deadline: Date | null
  status: string
}

/**
 * Additive boost for scoreNeed. Zero whenever isUrgent is false, confidence
 * is unset, the deadline has passed, or the need isn't open — so a non-urgent
 * need's score is byte-identical to before this file existed. Otherwise ramps
 * from 0 up to `URGENCY_MAX_BOOST * confidence` as the deadline approaches,
 * so a moderately-justified claim gets a proportional nudge rather than a
 * flat on/off boost.
 */
export function computeUrgencyBoost(need: UrgencyRankInput, now: Date = new Date()): number {
  if (!need.isUrgent) return 0
  if (need.urgencyConfidence == null) return 0
  if (need.status !== 'OPEN' && need.status !== 'IN_PROGRESS') return 0
  if (!need.deadline || need.deadline.getTime() <= now.getTime()) return 0

  const hoursRemaining = (need.deadline.getTime() - now.getTime()) / 3_600_000
  const ramp = clamp01(1 - hoursRemaining / URGENCY_RAMP_HOURS)
  return ramp * clamp01(need.urgencyConfidence) * URGENCY_MAX_BOOST
}

// ── Rescue Mode (pure — no I/O) ──────────────────────────────────────────────

export type RescueStage = 0 | 1 | 2 | 3

/**
 * Rescue Mode stage for an urgent need getting little to no traction as its
 * deadline nears. "Little or no engagement" is read here as zero accepted
 * interest — a single response is enough to stand the need down from rescue,
 * since the point is surfacing needs nobody has noticed yet, not needs
 * already in progress.
 *
 * Gated on RESCUE_MIN_CONFIDENCE so this only ever expands visibility for
 * needs the evaluation believes are genuinely urgent — never a reward for a
 * claim already flagged as weak.
 *
 * Stage 1 has no extra mechanism of its own: by the time it applies (< 24h
 * out), computeUrgencyBoost is already near its ramp ceiling, which *is* the
 * "increase exposure among relevant nearby users" the spec asks for. Stages 2
 * and 3 add the further, bounded mechanisms below.
 */
export function computeRescueStage(
  need: UrgencyRankInput,
  responseCount: number,
  now: Date = new Date(),
): RescueStage {
  if (!need.isUrgent) return 0
  if (need.urgencyConfidence == null || need.urgencyConfidence < RESCUE_MIN_CONFIDENCE) return 0
  if (need.status !== 'OPEN' && need.status !== 'IN_PROGRESS') return 0
  if (!need.deadline) return 0
  if (responseCount > 0) return 0

  const hoursRemaining = (need.deadline.getTime() - now.getTime()) / 3_600_000
  if (hoursRemaining <= 0) return 0
  if (hoursRemaining <= RESCUE_STAGE_HOURS[3]) return 3
  if (hoursRemaining <= RESCUE_STAGE_HOURS[2]) return 2
  if (hoursRemaining <= RESCUE_STAGE_HOURS[1]) return 1
  return 0
}

/** Stage 2+: how far past the viewer's chosen distance cutoff this need may
 * still surface. 1 (no change) below stage 2. */
export function rescueDistanceMultiplier(stage: RescueStage): number {
  return RESCUE_DISTANCE_MULTIPLIER[stage]
}

/** Stage 3 only: a small, fixed, capped addition on top of computeUrgencyBoost
 * — "slightly relax relevance" implemented as a bounded nudge, not a floor
 * that could shove a low-relevance need above genuinely strong matches. */
export function rescueScoreBonus(stage: RescueStage): number {
  return stage === 3 ? RESCUE_STAGE3_BONUS : 0
}

/**
 * Total urgency contribution to a need's rank score: the deadline-proximity
 * boost plus any Rescue Mode bonus. The single source of truth for "how much
 * did urgency add here" — scoreNeed folds it straight into the total, and
 * the feed's visibility cap (see selectBoostedWithinCap) uses this same
 * number to know exactly how much to subtract back out for needs beyond the
 * cap, returning them to precisely their non-urgent score.
 */
export function urgencyRankContribution(need: UrgencyRankInput, responseCount: number, now: Date = new Date()): number {
  return computeUrgencyBoost(need, now) + rescueScoreBonus(computeRescueStage(need, responseCount, now))
}

// ── Expiry (pure predicate — no I/O) ────────────────────────────────────────

/**
 * Whether an urgent need's deadline has passed. Used at read time in the feed
 * query and the detail view, so exclusion from discovery never depends on a
 * background write having completed — the same lazy-filter pattern already
 * used for distance and gender in feed_tab.dart's server-side counterpart.
 */
export function isExpired(need: { isUrgent: boolean; deadline: Date | null; status: string }, now: Date = new Date()): boolean {
  if (!need.isUrgent || !need.deadline) return false
  if (need.status === 'FULFILLED' || need.status === 'CLOSED' || need.status === 'EXPIRED') return false
  return need.deadline.getTime() <= now.getTime()
}

/**
 * Best-effort status flip to EXPIRED once a deadline has passed, plus the
 * matching reliability update. Fire-and-forget by design (callers should not
 * await this on a response path) — the read-time `isExpired` predicate above
 * is what actually guarantees an expired need drops out of discovery, so a
 * delayed or failed write here degrades nothing user-visible.
 */
export async function expireIfNeeded(need: {
  id: string
  posterId: string
  isUrgent: boolean
  deadline: Date | null
  status: string
  responseCount: number
}): Promise<void> {
  if (!isExpired(need)) return
  try {
    await prisma.need.updateMany({
      where: { id: need.id, status: { in: ['OPEN', 'IN_PROGRESS'] } },
      data: { status: 'EXPIRED' },
    })
    // Expired with nobody ever having responded reads as an unjustified claim.
    // Expired mid-conversation (someone did respond) is not scored as misuse —
    // that is a fulfilment that didn't land in time, not a false alarm.
    if (need.responseCount === 0) {
      await nudgeReliability(need.posterId, 'misused')
    }
  } catch (err) {
    console.error('[urgency] failed to expire need', need.id, err)
  }
}

// ── Urgency Reliability (I/O — never exposed to any client) ────────────────

/** Call once, right after an urgent need is created, before evaluation. */
export async function recordUrgentNeedCreated(userId: string): Promise<void> {
  try {
    await prisma.urgencyProfile.upsert({
      where: { userId },
      create: { userId, urgentCount: 1 },
      update: { urgentCount: { increment: 1 } },
    })
  } catch (err) {
    console.error('[urgency] failed to record urgent-need creation', userId, err)
  }
}

/** Call when an urgent need reaches FULFILLED before its deadline. */
export async function recordUrgentNeedFulfilled(userId: string): Promise<void> {
  await nudgeReliability(userId, 'justified')
}

async function nudgeReliability(userId: string, outcome: 'justified' | 'misused'): Promise<void> {
  try {
    const delta = outcome === 'justified' ? RELIABILITY_NUDGE_UP : -RELIABILITY_NUDGE_DOWN
    // Read-then-write rather than an atomic increment, since Prisma has no
    // server-side clamp. A lost update from two concurrent nudges on the same
    // user is a low-stakes, rare edge case for an internal soft signal — not
    // worth transaction complexity here.
    const existing = await prisma.urgencyProfile.findUnique({ where: { userId } })
    const nextReliability = clamp01((existing?.reliability ?? RELIABILITY_NEUTRAL) + delta)
    await prisma.urgencyProfile.upsert({
      where: { userId },
      create: {
        userId,
        reliability: nextReliability,
        justifiedCount: outcome === 'justified' ? 1 : 0,
        misusedCount: outcome === 'misused' ? 1 : 0,
      },
      update: {
        reliability: nextReliability,
        justifiedCount: outcome === 'justified' ? { increment: 1 } : undefined,
        misusedCount: outcome === 'misused' ? { increment: 1 } : undefined,
      },
    })
  } catch (err) {
    console.error('[urgency] failed to update reliability', userId, outcome, err)
  }
}

/** Reliability for a user, or the neutral default for someone who has never
 * used Urgency Mode. Read by evaluateUrgency; never returned to a client. */
export async function getReliability(userId: string): Promise<number> {
  try {
    const profile = await prisma.urgencyProfile.findUnique({ where: { userId } })
    return profile?.reliability ?? RELIABILITY_NEUTRAL
  } catch (err) {
    console.error('[urgency] failed to read reliability, using neutral', userId, err)
    return RELIABILITY_NEUTRAL
  }
}

function clamp01(n: number): number {
  return Math.max(0, Math.min(1, n))
}

// ── Orchestration: evaluate a freshly-created urgent need and store it ──────

export interface UrgentNeedRecord {
  id: string
  posterId: string
  title: string
  description: string
  needType: 'EARN' | 'CONNECT'
  earnCategory: EarnCategory | null
  connectCategory: ConnectCategory | null
  deadline: Date | null
  createdAt: Date
  renewalGeneration: number
}

/**
 * Gathers every input evaluateUrgency needs (trust score, this poster's
 * urgency track record, local market pressure), runs the evaluation, and
 * writes the result plus an internal-only UrgencyEvaluationLog row. Called
 * fire-and-forget right after an urgent need is created (POST /needs), after
 * it is renewed (POST /needs/:id/renew), and after an edit that changes its
 * title, description or deadline (PATCH /needs/:id) — the same function
 * serves all three, since each is just "this need's urgency claim needs a
 * fresh look." Never awaited on a response path, so it can take its time
 * without ever delaying the user's action.
 *
 * A need with no deadline should not reach here (creation validates that
 * isUrgent requires one), but this stays a no-op rather than throwing if it
 * ever does, consistent with every other function in this file.
 */
export async function evaluateAndStoreUrgency(
  need: UrgentNeedRecord,
  userId: string,
): Promise<void> {
  if (!need.deadline) return
  const deadline = need.deadline

  await recordUrgentNeedCreated(userId)

  const [user, record, reliability, pressure, eligibleVouchCount] = await Promise.all([
    prisma.user.findUnique({
      where: { id: userId },
      select: { emailVerifiedAt: true, phoneVerifiedAt: true, profile: { select: { faceVerifiedAt: true, idVerifiedAt: true } } },
    }),
    fetchTrackRecord(userId),
    getReliability(userId),
    marketPressure(need.needType, need.earnCategory, need.connectCategory),
    countTrustEligibleVouches(userId),
  ])

  // Same inputs the profile endpoints compute trust score and badges from
  // (see profiles.router.ts) — reused here so "user trust score" in the
  // evaluation is the identical number shown on their profile, not a second,
  // divergent calculation.
  const verification = {
    emailVerifiedAt: user?.emailVerifiedAt ?? null,
    phoneVerifiedAt: user?.phoneVerifiedAt ?? null,
    faceVerifiedAt: user?.profile?.faceVerifiedAt ?? null,
    idVerifiedAt: user?.profile?.idVerifiedAt ?? null,
  }
  const badgeInputs = { ...verification, ...record }
  const trustScore = computeTrustScore({
    ...verification,
    approvedCertificateCount: record.approvedCertificateCount,
    fulfilledNeedCount: totalFulfilledCount(record),
    avgRating: record.avgRating,
    ratingCount: record.ratingCount,
    earnedBadgeCount: earnedBadgeCount(badgeInputs),
    validatedSkillEndorsementCount: eligibleVouchCount,
  })

  const result = await evaluateUrgency({
    title: need.title,
    description: need.description,
    category: need.earnCategory ?? need.connectCategory ?? need.needType,
    deadline,
    createdAt: need.createdAt,
    trustScore,
    reliability,
    marketPressure: pressure,
    renewalGeneration: need.renewalGeneration,
  })

  try {
    await prisma.need.update({
      where: { id: need.id },
      data: { urgencyConfidence: result.confidence },
    })
  } catch (err) {
    console.error('[urgency] failed to store confidence for need', need.id, err)
  }

  // Internal-only — see UrgencyEvaluationLog's doc comment in schema.prisma.
  // A logging failure must never be treated as an evaluation failure.
  try {
    await prisma.urgencyEvaluationLog.create({
      data: {
        needId: need.id,
        confidence: result.confidence,
        reasoning: result.reasoning,
        usedLlm: result.usedLlm,
        renewalGeneration: need.renewalGeneration,
      },
    })
  } catch (err) {
    console.error('[urgency] failed to write evaluation log for need', need.id, err)
  }
}

// ── Response hygiene ─────────────────────────────────────────────────────────

/**
 * Strip `urgencyConfidence` from a Need (or any object shaped like one)
 * before it is returned to a client or broadcast over a socket.
 *
 * This codebase returns raw Prisma rows directly (`res.json({ ...need })`,
 * `io.emit('new_need', need)`) with no field allowlist, so a new nullable
 * column is otherwise serialized automatically the moment it exists — the
 * one place this feature could silently violate requirement 3 without the
 * type system catching it. `isUrgent` is intentionally left in: whether
 * Urgency Mode is on is the one thing a user is meant to see.
 */
export function stripInternalUrgencyFields<T extends { urgencyConfidence?: unknown }>(
  need: T,
): Omit<T, 'urgencyConfidence'> {
  const { urgencyConfidence: _drop, ...rest } = need
  return rest
}
