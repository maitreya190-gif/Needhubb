/**
 * Seasonal Impact League — recurring 3-month seasons, a permanent Hall of
 * Impact, seasonal badges and milestone achievements.
 *
 * This module never reads or writes `Profile.pointsTotal` and never changes
 * how a `PointsLedger` row is created — lifetime Impact Points, Trust Score
 * (`trust-score.ts`) and the feed's ranking (`needs.router.ts` scoreNeed) are
 * untouched by anything here. A season's points are simply
 * `SUM(delta) WHERE delta > 0` over `PointsLedger` for a fixed date range —
 * the existing ledger is the only source of truth, read differently.
 *
 * Mirrors the "derive, don't store" philosophy of `badges.ts`: the only
 * genuinely persisted state is `Season` (boundaries can't be derived) and
 * `SeasonRankSnapshot` (a permanent record written once, at the moment a
 * season ends — after that it is read-only forever). Everything else —
 * achievements, the seasonal-badge list on a profile, the live leaderboard —
 * is computed at read time from those two plus the existing ledger.
 *
 * There is no cron/worker in this stack, so the season lifecycle uses the
 * same lazy, on-read transition idiom as Urgency Mode's `expireIfNeeded` in
 * `urgency.ts`: `ensureCurrentSeason()` rolls over an ended season the
 * moment any league endpoint is next hit.
 */

import { prisma } from './prisma'
import type { Season as SeasonRow } from '@prisma/client'

// ── Tuning constants — the only place these live ────────────────────────────

export const SEASON_LENGTH_MONTHS = 3

/** Rank → permanent badge id, awarded once at season end. Never re-evaluated. */
export const SEASON_BADGE_IDS: Record<number, string> = {
  1: 'impact_champion',
  2: 'impact_elite',
  3: 'impact_pioneer',
  4: 'community_leader',
  5: 'rising_contributor',
}

export const SEASON_BADGE_LABELS: Record<string, string> = {
  impact_champion: 'Impact Champion',
  impact_elite: 'Impact Elite',
  impact_pioneer: 'Impact Pioneer',
  community_leader: 'Community Leader',
  rising_contributor: 'Rising Contributor',
}

/** Lifetime Impact Point totals that unlock a permanent milestone achievement. */
export const IMPACT_POINT_MILESTONES = [500, 1000, 2500, 5000, 10000]

/** Seasons in a row, finishing top 5, required for the streak achievement. */
export const CONSECUTIVE_TOP5_STREAK = 3

/** How long a computed leaderboard page stays cached in-process. There is no
 * Redis in this stack; a short in-memory TTL is proportionate. */
export const LEADERBOARD_CACHE_TTL_MS = 60_000

/** Rank thresholds the motivation system nudges a user toward. */
export const MOTIVATION_THRESHOLDS = [100, 10, 5]

/** How close to a threshold (in ranks) before the motivation hint appears —
 * keeps it "subtle," per the spec, rather than showing on every rank. */
export const MOTIVATION_LOOKAHEAD = 10

export const MAX_FEATURED_ACHIEVEMENTS = 3

const MAX_SEASON_CATCHUP_ITERATIONS = 24

// ── Types ────────────────────────────────────────────────────────────────

export interface SeasonInfo {
  id: string
  seasonNumber: number
  year: number
  startsAt: Date
  endsAt: Date
  status: 'ACTIVE' | 'ARCHIVED'
}

export interface LeaderboardEntry {
  rank: number
  userId: string
  displayName: string
  avatarUrl: string | null
  seasonPoints: number
  lifetimePoints: number
  badgeId: string | null
}

export interface MotivationHint {
  label: string
  spotsAway: number
}

export interface MyRank {
  rank: number | null
  seasonPoints: number
  lifetimePoints: number
  nearestMilestone: MotivationHint | null
}

export interface SeasonHistoryRow {
  seasonNumber: number
  year: number
  rank: number
  seasonPoints: number
  seasonEndedAt: Date
  badgeId: string | null
}

export interface SeasonalBadgeDisplay {
  badgeId: string
  label: string
  seasonNumber: number
  year: number
  rank: number
}

export interface HallOfImpactEntry {
  seasonNumber: number
  year: number
  rank: number
  badgeId: string
  userId: string
  displayName: string
  avatarUrl: string | null
}

export interface LeagueAchievement {
  id: string
  label: string
  description: string
  category: 'participation' | 'ranking' | 'points'
  earned: boolean
  earnedAt: Date | null
}

export interface LeagueAchievementInputs {
  lifetimePoints: number
  /** This user's permanent season history — order does not matter, callers
   * pass whatever fetchSeasonHistory returns. */
  seasonHistory: SeasonHistoryRow[]
  /** When lifetime points first crossed each configured milestone, if known. */
  milestoneReachedAt: Map<number, Date>
}

// ── Season lifecycle ─────────────────────────────────────────────────────

let cachedSeason: { season: SeasonInfo; expiresAt: number } | null = null

/** Test-only: clears the in-process season/leaderboard caches so each test
 * starts from a clean slate regardless of what timestamps neighboring tests
 * used. Never called from application code. */
export function __resetImpactLeagueCachesForTests(): void {
  cachedSeason = null
  leaderboardCache.clear()
}

function addMonthsUtc(d: Date, months: number): Date {
  const next = new Date(d)
  next.setUTCMonth(next.getUTCMonth() + months)
  return next
}

function toSeasonInfo(row: SeasonRow): SeasonInfo {
  return {
    id: row.id,
    seasonNumber: row.seasonNumber,
    year: row.year,
    startsAt: row.startsAt,
    endsAt: row.endsAt,
    status: row.status,
  }
}

/** Used only if the DB is unreachable — never persisted. Keeps read
 * endpoints returning a sane, if imprecise, season instead of a 500. */
function fallbackSeason(now: Date): SeasonInfo {
  const quarterStartMonth = Math.floor(now.getUTCMonth() / SEASON_LENGTH_MONTHS) * SEASON_LENGTH_MONTHS
  const startsAt = new Date(Date.UTC(now.getUTCFullYear(), quarterStartMonth, 1))
  return {
    id: 'fallback',
    seasonNumber: 0,
    year: startsAt.getUTCFullYear(),
    startsAt,
    endsAt: addMonthsUtc(startsAt, SEASON_LENGTH_MONTHS),
    status: 'ACTIVE',
  }
}

async function bootstrapFirstSeason(now: Date): Promise<SeasonRow> {
  try {
    return await prisma.season.create({
      data: {
        seasonNumber: 1,
        year: now.getUTCFullYear(),
        startsAt: now,
        endsAt: addMonthsUtc(now, SEASON_LENGTH_MONTHS),
        status: 'ACTIVE',
      },
    })
  } catch (err) {
    // Concurrent first request already created it — the unique constraint on
    // seasonNumber is what makes this race safe to just retry as a read.
    const existing = await prisma.season.findUnique({ where: { seasonNumber: 1 } })
    if (existing) return existing
    throw err
  }
}

/**
 * Positive ledger entries are strictly increasing, so a user's running sum
 * can only equal their season-final total once — at their very last
 * positive entry of the season. That timestamp is exactly "when they
 * achieved their final score," which is what requirement 9's tie-break rule
 * asks for: whoever got there earlier ranks above an equal-scoring rival.
 */
async function finalizeSeasonSnapshot(season: SeasonRow): Promise<void> {
  const entries = await prisma.pointsLedger.findMany({
    where: { delta: { gt: 0 }, createdAt: { gte: season.startsAt, lt: season.endsAt } },
    select: { userId: true, delta: true, createdAt: true },
    orderBy: { createdAt: 'asc' },
  })
  if (entries.length === 0) return

  const totals = new Map<string, number>()
  const lastEntryAt = new Map<string, Date>()
  for (const e of entries) {
    totals.set(e.userId, (totals.get(e.userId) ?? 0) + e.delta)
    lastEntryAt.set(e.userId, e.createdAt) // entries are createdAt-ascending, so this ends up as the last one
  }

  const ranked = [...totals.entries()]
    .map(([userId, seasonPoints]) => ({ userId, seasonPoints, reachedAt: lastEntryAt.get(userId)! }))
    .sort((a, b) => b.seasonPoints - a.seasonPoints || a.reachedAt.getTime() - b.reachedAt.getTime())

  const rows = ranked.map((r, i) => ({
    seasonId: season.id,
    userId: r.userId,
    rank: i + 1,
    seasonPoints: r.seasonPoints,
    badgeId: SEASON_BADGE_IDS[i + 1] ?? null,
  }))

  try {
    await prisma.seasonRankSnapshot.createMany({ data: rows, skipDuplicates: true })
  } catch (err) {
    console.error('[impact-league] failed to write season rank snapshot for season', season.seasonNumber, err)
  }
}

async function rolloverSeason(active: SeasonRow, now: Date): Promise<SeasonRow> {
  // Idempotent guard: only the request that actually flips ACTIVE→ARCHIVED
  // finalizes the snapshot, so two concurrent requests hitting the boundary
  // at once cannot double-write it.
  const archived = await prisma.season.updateMany({
    where: { id: active.id, status: 'ACTIVE' },
    data: { status: 'ARCHIVED', archivedAt: now },
  })
  if (archived.count > 0) {
    await finalizeSeasonSnapshot(active)
  }

  const nextNumber = active.seasonNumber + 1
  try {
    return await prisma.season.create({
      data: {
        seasonNumber: nextNumber,
        year: active.endsAt.getUTCFullYear(),
        startsAt: active.endsAt,
        endsAt: addMonthsUtc(active.endsAt, SEASON_LENGTH_MONTHS),
        status: 'ACTIVE',
      },
    })
  } catch (err) {
    const existing = await prisma.season.findUnique({ where: { seasonNumber: nextNumber } })
    if (existing) return existing
    throw err
  }
}

/**
 * Returns the current active season, bootstrapping the first one ever and
 * lazily rolling over any that have ended (looped, so the app catching up
 * after being idle across more than one season boundary still ends up
 * correct). Call this first in every league endpoint — same idiom as
 * `expireIfNeeded` in urgency.ts, just synchronous, since callers need a
 * real season id to query against.
 */
export async function ensureCurrentSeason(now: Date = new Date()): Promise<SeasonInfo> {
  if (cachedSeason && cachedSeason.expiresAt > now.getTime()) return cachedSeason.season
  try {
    let active = (await prisma.season.findFirst({ where: { status: 'ACTIVE' }, orderBy: { seasonNumber: 'desc' } }))
      ?? (await bootstrapFirstSeason(now))

    let iterations = 0
    while (now.getTime() >= active.endsAt.getTime() && iterations < MAX_SEASON_CATCHUP_ITERATIONS) {
      active = await rolloverSeason(active, now)
      iterations++
    }

    const info = toSeasonInfo(active)
    cachedSeason = { season: info, expiresAt: now.getTime() + LEADERBOARD_CACHE_TTL_MS }
    return info
  } catch (err) {
    console.error('[impact-league] failed to resolve current season, using in-memory fallback', err)
    return fallbackSeason(now)
  }
}

// ── Live leaderboard (current, in-progress season) ──────────────────────

interface LeaderboardCacheEntry { rows: LeaderboardEntry[]; expiresAt: number }
const leaderboardCache = new Map<string, LeaderboardCacheEntry>()

/**
 * Current season's leaderboard, computed live from PointsLedger (never
 * snapshotted while a season is in progress). Tie-break here is an
 * approximation (earliest-activity, via `_min: createdAt`) rather than the
 * exact "earliest reached final score" rule — that rule is only meaningful
 * once a season's outcome is actually final, which is why the precise
 * version runs in `finalizeSeasonSnapshot` instead.
 */
export async function getCurrentLeaderboard(opts: {
  take?: number
  scope?: 'global' | 'friends'
  userId?: string
} = {}): Promise<LeaderboardEntry[]> {
  const take = Math.max(1, Math.min(opts.take ?? 50, 200))
  const scope = opts.scope ?? 'global'

  try {
    const season = await ensureCurrentSeason()
    const cacheKey = `${season.id}:${scope}:${scope === 'friends' ? opts.userId ?? '' : ''}:${take}`
    const now = Date.now()
    const cached = leaderboardCache.get(cacheKey)
    if (cached && cached.expiresAt > now) return cached.rows

    let friendUserIds: string[] | null = null
    if (scope === 'friends') {
      if (!opts.userId) return []
      const friendships = await prisma.friendship.findMany({
        where: { OR: [{ userAId: opts.userId }, { userBId: opts.userId }] },
        select: { userAId: true, userBId: true },
      })
      friendUserIds = [
        opts.userId,
        ...friendships.map((f) => (f.userAId === opts.userId ? f.userBId : f.userAId)),
      ]
    }

    const grouped = await prisma.pointsLedger.groupBy({
      by: ['userId'],
      where: {
        delta: { gt: 0 },
        createdAt: { gte: season.startsAt, lt: season.endsAt },
        ...(friendUserIds ? { userId: { in: friendUserIds } } : {}),
      },
      _sum: { delta: true },
      _min: { createdAt: true },
      orderBy: { _sum: { delta: 'desc' } },
      take,
    })
    if (grouped.length === 0) return []

    const userIds = grouped.map((g) => g.userId)
    const [users, profiles, badgeRows] = await Promise.all([
      prisma.user.findMany({ where: { id: { in: userIds } }, select: { id: true, displayName: true } }),
      prisma.profile.findMany({ where: { userId: { in: userIds } }, select: { userId: true, avatarUrl: true, pointsTotal: true } }),
      prisma.seasonRankSnapshot.findMany({
        where: { userId: { in: userIds }, badgeId: { not: null } },
        select: { userId: true, badgeId: true },
        orderBy: { createdAt: 'desc' },
      }),
    ])
    const userMap = new Map(users.map((u) => [u.id, u]))
    const profileMap = new Map(profiles.map((p) => [p.userId, p]))
    const badgeMap = new Map<string, string>()
    for (const b of badgeRows) if (b.badgeId && !badgeMap.has(b.userId)) badgeMap.set(b.userId, b.badgeId)

    const rows: LeaderboardEntry[] = grouped
      .slice()
      .sort((a, b) =>
        (b._sum.delta ?? 0) - (a._sum.delta ?? 0) ||
        (a._min.createdAt?.getTime() ?? 0) - (b._min.createdAt?.getTime() ?? 0),
      )
      .map((g, i) => ({
        rank: i + 1,
        userId: g.userId,
        displayName: userMap.get(g.userId)?.displayName ?? 'Someone',
        avatarUrl: profileMap.get(g.userId)?.avatarUrl ?? null,
        seasonPoints: g._sum.delta ?? 0,
        lifetimePoints: profileMap.get(g.userId)?.pointsTotal ?? 0,
        badgeId: badgeMap.get(g.userId) ?? null,
      }))

    leaderboardCache.set(cacheKey, { rows, expiresAt: now + LEADERBOARD_CACHE_TTL_MS })
    return rows
  } catch (err) {
    console.error('[impact-league] failed to compute leaderboard', err)
    return []
  }
}

function nearestMotivationMilestone(rank: number): MotivationHint | null {
  let best: MotivationHint | null = null
  for (const threshold of MOTIVATION_THRESHOLDS) {
    if (rank <= threshold) continue
    const spotsAway = rank - threshold
    if (spotsAway > MOTIVATION_LOOKAHEAD) continue
    if (!best || spotsAway < best.spotsAway) best = { label: `Top ${threshold}`, spotsAway }
  }
  return best
}

/** One user's current-season standing, plus a subtle nudge if they're close
 * to a notable rank threshold — the entire "motivation system" (requirement
 * 8). No notification is ever sent from here; this is one extra field in a
 * response the client already has to fetch. */
export async function getMyRank(userId: string): Promise<MyRank> {
  try {
    const season = await ensureCurrentSeason()
    const [mine, profile] = await Promise.all([
      prisma.pointsLedger.aggregate({
        where: { userId, delta: { gt: 0 }, createdAt: { gte: season.startsAt, lt: season.endsAt } },
        _sum: { delta: true },
      }),
      prisma.profile.findUnique({ where: { userId }, select: { pointsTotal: true } }),
    ])
    const seasonPoints = mine._sum.delta ?? 0

    let rank: number | null = null
    if (seasonPoints > 0) {
      const ahead = await prisma.pointsLedger.groupBy({
        by: ['userId'],
        where: { delta: { gt: 0 }, createdAt: { gte: season.startsAt, lt: season.endsAt } },
        _sum: { delta: true },
        having: { delta: { _sum: { gt: seasonPoints } } },
      })
      rank = ahead.length + 1
    }

    return {
      rank,
      seasonPoints,
      lifetimePoints: profile?.pointsTotal ?? 0,
      nearestMilestone: rank == null ? null : nearestMotivationMilestone(rank),
    }
  } catch (err) {
    console.error('[impact-league] failed to compute my-rank', userId, err)
    return { rank: null, seasonPoints: 0, lifetimePoints: 0, nearestMilestone: null }
  }
}

// ── Archive & Hall of Impact (permanent, read-only) ─────────────────────

export async function getSeasonArchive(seasonNumber: number): Promise<{ season: SeasonInfo; rows: LeaderboardEntry[] } | null> {
  try {
    const season = await prisma.season.findUnique({ where: { seasonNumber } })
    if (!season || season.status !== 'ARCHIVED') return null

    const snapshots = await prisma.seasonRankSnapshot.findMany({
      where: { seasonId: season.id },
      orderBy: { rank: 'asc' },
    })
    const userIds = snapshots.map((s) => s.userId)
    const [users, profiles] = await Promise.all([
      prisma.user.findMany({ where: { id: { in: userIds } }, select: { id: true, displayName: true } }),
      prisma.profile.findMany({ where: { userId: { in: userIds } }, select: { userId: true, avatarUrl: true, pointsTotal: true } }),
    ])
    const userMap = new Map(users.map((u) => [u.id, u]))
    const profileMap = new Map(profiles.map((p) => [p.userId, p]))

    const rows: LeaderboardEntry[] = snapshots.map((s) => ({
      rank: s.rank,
      userId: s.userId,
      displayName: userMap.get(s.userId)?.displayName ?? 'Someone',
      avatarUrl: profileMap.get(s.userId)?.avatarUrl ?? null,
      seasonPoints: s.seasonPoints,
      lifetimePoints: profileMap.get(s.userId)?.pointsTotal ?? 0,
      badgeId: s.badgeId,
    }))
    return { season: toSeasonInfo(season), rows }
  } catch (err) {
    console.error('[impact-league] failed to load season archive', seasonNumber, err)
    return null
  }
}

export async function getHallOfImpact(): Promise<HallOfImpactEntry[]> {
  try {
    const rows = await prisma.seasonRankSnapshot.findMany({
      where: { badgeId: { not: null } },
      include: { season: { select: { seasonNumber: true, year: true } } },
      orderBy: [{ season: { seasonNumber: 'desc' } }, { rank: 'asc' }],
    })
    const userIds = [...new Set(rows.map((r) => r.userId))]
    const [users, profiles] = await Promise.all([
      prisma.user.findMany({ where: { id: { in: userIds } }, select: { id: true, displayName: true } }),
      prisma.profile.findMany({ where: { userId: { in: userIds } }, select: { userId: true, avatarUrl: true } }),
    ])
    const userMap = new Map(users.map((u) => [u.id, u]))
    const profileMap = new Map(profiles.map((p) => [p.userId, p]))

    return rows.map((r) => ({
      seasonNumber: r.season.seasonNumber,
      year: r.season.year,
      rank: r.rank,
      badgeId: r.badgeId as string,
      userId: r.userId,
      displayName: userMap.get(r.userId)?.displayName ?? 'Someone',
      avatarUrl: profileMap.get(r.userId)?.avatarUrl ?? null,
    }))
  } catch (err) {
    console.error('[impact-league] failed to load hall of impact', err)
    return []
  }
}

/** A user's full permanent season history — backs both the seasonal-badge
 * list on a profile and achievement derivation below. */
export async function fetchSeasonHistory(userId: string): Promise<SeasonHistoryRow[]> {
  try {
    const snapshots = await prisma.seasonRankSnapshot.findMany({
      where: { userId },
      include: { season: { select: { seasonNumber: true, year: true, endsAt: true } } },
      orderBy: { season: { seasonNumber: 'asc' } },
    })
    return snapshots.map((s) => ({
      seasonNumber: s.season.seasonNumber,
      year: s.season.year,
      rank: s.rank,
      seasonPoints: s.seasonPoints,
      seasonEndedAt: s.season.endsAt,
      badgeId: s.badgeId,
    }))
  } catch (err) {
    console.error('[impact-league] failed to load season history', userId, err)
    return []
  }
}

export function seasonalBadgesFromHistory(history: SeasonHistoryRow[]): SeasonalBadgeDisplay[] {
  return history
    .filter((h): h is SeasonHistoryRow & { badgeId: string } => h.badgeId != null)
    .map((h) => ({
      badgeId: h.badgeId,
      label: SEASON_BADGE_LABELS[h.badgeId] ?? h.badgeId,
      seasonNumber: h.seasonNumber,
      year: h.year,
      rank: h.rank,
    }))
}

/** When this user's lifetime positive-point total first crossed each
 * configured milestone — used only to caption achievements with a date. */
export async function fetchMilestoneTimestamps(userId: string): Promise<Map<number, Date>> {
  const result = new Map<number, Date>()
  try {
    const entries = await prisma.pointsLedger.findMany({
      where: { userId, delta: { gt: 0 } },
      select: { delta: true, createdAt: true },
      orderBy: { createdAt: 'asc' },
    })
    const remaining = [...IMPACT_POINT_MILESTONES].sort((a, b) => a - b)
    let running = 0
    for (const e of entries) {
      running += e.delta
      while (remaining.length > 0 && running >= remaining[0]) {
        result.set(remaining.shift()!, e.createdAt)
      }
      if (remaining.length === 0) break
    }
  } catch (err) {
    console.error('[impact-league] failed to compute milestone timestamps', userId, err)
  }
  return result
}

// ── Milestone achievements (pure, derived — mirrors badges.ts) ──────────

interface LeagueAchievementDefinition extends Omit<LeagueAchievement, 'earned' | 'earnedAt'> {
  isEarned: (i: LeagueAchievementInputs) => boolean
  earnedAt: (i: LeagueAchievementInputs) => Date | null
}

function longestConsecutiveTop5Streak(history: SeasonHistoryRow[]): number {
  const sorted = [...history].sort((a, b) => a.seasonNumber - b.seasonNumber)
  let longest = 0
  let current = 0
  let prevSeasonNumber: number | null = null
  for (const s of sorted) {
    const isConsecutive = prevSeasonNumber != null && s.seasonNumber === prevSeasonNumber + 1
    current = s.rank <= 5 ? (isConsecutive ? current + 1 : 1) : 0
    longest = Math.max(longest, current)
    prevSeasonNumber = s.seasonNumber
  }
  return longest
}

function consecutiveTop5StreakEndedAt(history: SeasonHistoryRow[]): Date | null {
  const sorted = [...history].sort((a, b) => a.seasonNumber - b.seasonNumber)
  let streak: SeasonHistoryRow[] = []
  let prevSeasonNumber: number | null = null
  for (const s of sorted) {
    const isConsecutive = prevSeasonNumber != null && s.seasonNumber === prevSeasonNumber + 1
    streak = s.rank <= 5 ? (isConsecutive ? [...streak, s] : [s]) : []
    if (streak.length >= CONSECUTIVE_TOP5_STREAK) return streak[CONSECUTIVE_TOP5_STREAK - 1].seasonEndedAt
    prevSeasonNumber = s.seasonNumber
  }
  return null
}

export const LEAGUE_ACHIEVEMENT_DEFINITIONS: LeagueAchievementDefinition[] = [
  {
    id: 'first_participation',
    label: 'First Seasonal Participation',
    description: 'Earn Impact Points during any Impact League season',
    category: 'participation',
    isEarned: (i) => i.seasonHistory.length >= 1,
    earnedAt: (i) => i.seasonHistory[0]?.seasonEndedAt ?? null,
  },
  {
    id: 'first_top_100',
    label: 'First Top 100 Finish',
    description: 'Finish a season ranked in the top 100',
    category: 'ranking',
    isEarned: (i) => i.seasonHistory.some((s) => s.rank <= 100),
    earnedAt: (i) => i.seasonHistory.find((s) => s.rank <= 100)?.seasonEndedAt ?? null,
  },
  {
    id: 'first_top_10',
    label: 'First Top 10 Finish',
    description: 'Finish a season ranked in the top 10',
    category: 'ranking',
    isEarned: (i) => i.seasonHistory.some((s) => s.rank <= 10),
    earnedAt: (i) => i.seasonHistory.find((s) => s.rank <= 10)?.seasonEndedAt ?? null,
  },
  {
    id: 'top_5_finish',
    label: 'Top 5 Finish',
    description: 'Finish a season ranked in the top 5',
    category: 'ranking',
    isEarned: (i) => i.seasonHistory.some((s) => s.rank <= 5),
    earnedAt: (i) => i.seasonHistory.find((s) => s.rank <= 5)?.seasonEndedAt ?? null,
  },
  {
    id: 'season_champion',
    label: 'Season Champion',
    description: 'Finish a season ranked #1',
    category: 'ranking',
    isEarned: (i) => i.seasonHistory.some((s) => s.rank === 1),
    earnedAt: (i) => i.seasonHistory.find((s) => s.rank === 1)?.seasonEndedAt ?? null,
  },
  {
    id: 'consecutive_top_5',
    label: 'Consecutive Top 5 Finishes',
    description: `Finish in the top 5 for ${CONSECUTIVE_TOP5_STREAK} seasons in a row`,
    category: 'ranking',
    isEarned: (i) => longestConsecutiveTop5Streak(i.seasonHistory) >= CONSECUTIVE_TOP5_STREAK,
    earnedAt: (i) => consecutiveTop5StreakEndedAt(i.seasonHistory),
  },
  {
    id: 'multiple_season_wins',
    label: 'Multiple Season Wins',
    description: 'Finish #1 in more than one season',
    category: 'ranking',
    isEarned: (i) => i.seasonHistory.filter((s) => s.rank === 1).length >= 2,
    earnedAt: (i) => {
      const wins = i.seasonHistory
        .filter((s) => s.rank === 1)
        .sort((a, b) => a.seasonEndedAt.getTime() - b.seasonEndedAt.getTime())
      return wins.length >= 2 ? wins[1].seasonEndedAt : null
    },
  },
  ...IMPACT_POINT_MILESTONES.map(
    (threshold): LeagueAchievementDefinition => ({
      id: `impact_milestone_${threshold}`,
      label: `${threshold.toLocaleString()} Impact Points`,
      description: `Reach ${threshold.toLocaleString()} lifetime Impact Points`,
      category: 'points',
      isEarned: (i) => i.lifetimePoints >= threshold,
      earnedAt: (i) => i.milestoneReachedAt.get(threshold) ?? null,
    }),
  ),
]

/** Every achievement with its earned state — unearned ones included, same
 * reasoning as `computeBadges`: an unearned achievement is a visible goal,
 * not a thing to hide. Never touches Trust Score or Impact Points. */
export function computeLeagueAchievements(inputs: LeagueAchievementInputs): LeagueAchievement[] {
  return LEAGUE_ACHIEVEMENT_DEFINITIONS.map(({ isEarned, earnedAt, ...rest }) => {
    const earned = isEarned(inputs)
    return { ...rest, earned, earnedAt: earned ? earnedAt(inputs) : null }
  })
}

// ── Featured achievements (the one user-editable piece of state) ────────

export async function setFeaturedAchievements(userId: string, achievementIds: string[]): Promise<string[]> {
  const validIds = new Set<string>([
    ...LEAGUE_ACHIEVEMENT_DEFINITIONS.map((d) => d.id),
    ...Object.values(SEASON_BADGE_IDS),
  ])
  const deduped = [...new Set(achievementIds)]
    .filter((id) => validIds.has(id))
    .slice(0, MAX_FEATURED_ACHIEVEMENTS)

  await prisma.profile.update({ where: { userId }, data: { featuredAchievementIds: deduped } })
  return deduped
}
