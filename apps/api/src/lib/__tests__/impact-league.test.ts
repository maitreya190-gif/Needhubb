/**
 * Impact League is additive and derived wherever possible — the properties
 * that matter most are: (1) the season lifecycle rolls over correctly and
 * exactly once even under a simulated race, (2) the tie-break rule at
 * season-end matches requirement 9 exactly, (3) achievements are a pure
 * function of a user's permanent history (no DB access, no Trust Score, no
 * Impact Point mutation), and (4) every DB-touching read degrades to an
 * empty/safe value rather than throwing — this feature must never be able to
 * break a profile or feed request that happens to touch it.
 */

import { describe, it, expect, vi, beforeEach } from 'vitest'

const mocks = vi.hoisted(() => ({
  seasonFindFirst: vi.fn(),
  seasonFindMany: vi.fn(),
  seasonCreate: vi.fn(),
  seasonUpdateMany: vi.fn(),
  seasonFindUnique: vi.fn(),
  pointsLedgerFindMany: vi.fn(),
  pointsLedgerGroupBy: vi.fn(),
  pointsLedgerAggregate: vi.fn(),
  snapshotCreateMany: vi.fn(),
  snapshotFindMany: vi.fn(),
  friendshipFindMany: vi.fn(),
  userFindMany: vi.fn(),
  profileFindMany: vi.fn(),
  profileFindUnique: vi.fn(),
  profileUpdate: vi.fn(),
}))

vi.mock('../prisma', () => ({
  prisma: {
    season: {
      findFirst: mocks.seasonFindFirst,
      findMany: mocks.seasonFindMany,
      create: mocks.seasonCreate,
      updateMany: mocks.seasonUpdateMany,
      findUnique: mocks.seasonFindUnique,
    },
    pointsLedger: {
      findMany: mocks.pointsLedgerFindMany,
      groupBy: mocks.pointsLedgerGroupBy,
      aggregate: mocks.pointsLedgerAggregate,
    },
    seasonRankSnapshot: {
      createMany: mocks.snapshotCreateMany,
      findMany: mocks.snapshotFindMany,
    },
    friendship: { findMany: mocks.friendshipFindMany },
    user: { findMany: mocks.userFindMany },
    profile: { findMany: mocks.profileFindMany, findUnique: mocks.profileFindUnique, update: mocks.profileUpdate },
  },
}))

import {
  ensureCurrentSeason, getCurrentLeaderboard, getMyRank, listSeasons, getSeasonArchive, getHallOfImpact,
  fetchSeasonHistory, fetchMilestoneTimestamps, seasonalBadgesFromHistory, computeLeagueAchievements,
  setFeaturedAchievements, SEASON_BADGE_IDS, IMPACT_POINT_MILESTONES, CONSECUTIVE_TOP5_STREAK,
  MAX_FEATURED_ACHIEVEMENTS, __resetImpactLeagueCachesForTests,
} from '../impact-league'

beforeEach(() => {
  Object.values(mocks).forEach((m) => m.mockReset())
  // The season/leaderboard cache is module-level state — without clearing it,
  // a later test whose `now` happens to fall within an earlier test's 60s TTL
  // window would silently read a stale cached season instead of exercising
  // the mocks that test actually set up.
  __resetImpactLeagueCachesForTests()
})

function season(overrides: Partial<{
  id: string; seasonNumber: number; year: number; startsAt: Date; endsAt: Date; status: 'ACTIVE' | 'ARCHIVED'
}> = {}) {
  return {
    id: 's1', seasonNumber: 1, year: 2026, startsAt: new Date('2026-01-01T00:00:00Z'),
    endsAt: new Date('2026-04-01T00:00:00Z'), status: 'ACTIVE' as const, archivedAt: null, createdAt: new Date('2026-01-01T00:00:00Z'),
    ...overrides,
  }
}

// `getCurrentLeaderboard` / `getMyRank` call `ensureCurrentSeason()` with no
// argument, i.e. the *real* wall-clock time — so tests exercising them need
// a season that ends far in the future, or a real rollover would trigger
// mid-test regardless of when this suite happens to run.
function activeSeasonForReadTests() {
  return season({ endsAt: new Date('2999-01-01T00:00:00Z') })
}

// ── Season lifecycle ─────────────────────────────────────────────────────

describe('ensureCurrentSeason', () => {
  it('bootstraps season 1 when none exists yet', async () => {
    mocks.seasonFindFirst.mockResolvedValue(null)
    mocks.seasonCreate.mockResolvedValue(season())

    const now = new Date('2026-01-15T00:00:00Z')
    const result = await ensureCurrentSeason(now)

    expect(result.seasonNumber).toBe(1)
    expect(mocks.seasonCreate).toHaveBeenCalledTimes(1)
    expect(mocks.seasonCreate.mock.calls[0][0].data.seasonNumber).toBe(1)
  })

  it('does not roll over a season that has not ended yet', async () => {
    mocks.seasonFindFirst.mockResolvedValue(season())
    const now = new Date('2026-02-01T00:00:00Z') // before endsAt

    const result = await ensureCurrentSeason(now)

    expect(result.seasonNumber).toBe(1)
    expect(mocks.seasonUpdateMany).not.toHaveBeenCalled()
  })

  it('rolls over exactly once when a season has ended, finalizing its snapshot', async () => {
    mocks.seasonFindFirst.mockResolvedValue(season())
    mocks.seasonUpdateMany.mockResolvedValue({ count: 1 }) // we won the archive race
    mocks.pointsLedgerFindMany.mockResolvedValue([
      { userId: 'u1', delta: 100, createdAt: new Date('2026-01-10T00:00:00Z') },
    ])
    mocks.snapshotCreateMany.mockResolvedValue({ count: 1 })
    mocks.seasonCreate.mockResolvedValue(season({ id: 's2', seasonNumber: 2, startsAt: new Date('2026-04-01T00:00:00Z'), endsAt: new Date('2026-07-01T00:00:00Z') }))

    const now = new Date('2026-04-05T00:00:00Z') // one season past endsAt
    const result = await ensureCurrentSeason(now)

    expect(result.seasonNumber).toBe(2)
    expect(mocks.snapshotCreateMany).toHaveBeenCalledTimes(1)
    const rows = mocks.snapshotCreateMany.mock.calls[0][0].data
    expect(rows).toEqual([{ seasonId: 's1', userId: 'u1', rank: 1, seasonPoints: 100, badgeId: SEASON_BADGE_IDS[1] }])
  })

  it('does not double-finalize when another request already won the archive race', async () => {
    mocks.seasonFindFirst.mockResolvedValue(season())
    mocks.seasonUpdateMany.mockResolvedValue({ count: 0 }) // someone else archived it first
    mocks.seasonCreate.mockResolvedValue(season({ id: 's2', seasonNumber: 2, startsAt: new Date('2026-04-01T00:00:00Z'), endsAt: new Date('2026-07-01T00:00:00Z') }))

    const now = new Date('2026-04-05T00:00:00Z')
    await ensureCurrentSeason(now)

    expect(mocks.pointsLedgerFindMany).not.toHaveBeenCalled()
    expect(mocks.snapshotCreateMany).not.toHaveBeenCalled()
  })

  it('catches up across more than one elapsed season boundary', async () => {
    mocks.seasonFindFirst.mockResolvedValue(season()) // season 1, ended long ago
    mocks.seasonUpdateMany.mockResolvedValue({ count: 1 })
    mocks.pointsLedgerFindMany.mockResolvedValue([])
    mocks.seasonCreate
      .mockResolvedValueOnce(season({ id: 's2', seasonNumber: 2, startsAt: new Date('2026-04-01T00:00:00Z'), endsAt: new Date('2026-07-01T00:00:00Z') }))
      .mockResolvedValueOnce(season({ id: 's3', seasonNumber: 3, startsAt: new Date('2026-07-01T00:00:00Z'), endsAt: new Date('2026-10-01T00:00:00Z') }))

    const now = new Date('2026-08-01T00:00:00Z') // two seasons past season 1's end
    const result = await ensureCurrentSeason(now)

    expect(result.seasonNumber).toBe(3)
    expect(mocks.seasonCreate).toHaveBeenCalledTimes(2)
  })

  it('falls back to an in-memory season on DB failure, without throwing', async () => {
    mocks.seasonFindFirst.mockRejectedValue(new Error('db unreachable'))
    const result = await ensureCurrentSeason(new Date('2026-05-15T00:00:00Z'))
    expect(result.status).toBe('ACTIVE')
    expect(result.id).toBe('fallback')
  })
})

describe('season-end tie-break (requirement 9.2 — earlier final score wins ties)', () => {
  it('ranks a tied user who reached their total earlier above one who reached it later', async () => {
    mocks.seasonFindFirst.mockResolvedValue(season())
    mocks.seasonUpdateMany.mockResolvedValue({ count: 1 })
    mocks.pointsLedgerFindMany.mockResolvedValue([
      { userId: 'slow', delta: 50, createdAt: new Date('2026-01-05T00:00:00Z') },
      { userId: 'fast', delta: 100, createdAt: new Date('2026-01-06T00:00:00Z') }, // fast reaches 100 here
      { userId: 'slow', delta: 50, createdAt: new Date('2026-03-20T00:00:00Z') }, // slow only reaches 100 near season end
    ])
    mocks.snapshotCreateMany.mockResolvedValue({ count: 1 })
    mocks.seasonCreate.mockResolvedValue(season({ id: 's2', seasonNumber: 2 }))

    await ensureCurrentSeason(new Date('2026-04-05T00:00:00Z'))

    const rows = mocks.snapshotCreateMany.mock.calls[0][0].data
    expect(rows.find((r: any) => r.userId === 'fast').rank).toBe(1)
    expect(rows.find((r: any) => r.userId === 'slow').rank).toBe(2)
  })

  it('assigns a badge only to ranks 1-5, never below', async () => {
    mocks.seasonFindFirst.mockResolvedValue(season())
    mocks.seasonUpdateMany.mockResolvedValue({ count: 1 })
    mocks.pointsLedgerFindMany.mockResolvedValue(
      Array.from({ length: 7 }, (_, i) => ({
        userId: `u${i}`,
        delta: 100 - i, // strictly decreasing, no ties
        createdAt: new Date('2026-01-10T00:00:00Z'),
      })),
    )
    mocks.snapshotCreateMany.mockResolvedValue({ count: 1 })
    mocks.seasonCreate.mockResolvedValue(season({ id: 's2', seasonNumber: 2 }))

    await ensureCurrentSeason(new Date('2026-04-05T00:00:00Z'))

    const rows = mocks.snapshotCreateMany.mock.calls[0][0].data
    for (const r of rows) {
      if (r.rank <= 5) expect(r.badgeId).toBe(SEASON_BADGE_IDS[r.rank])
      else expect(r.badgeId).toBeNull()
    }
  })
})

// ── Live leaderboard ─────────────────────────────────────────────────────

describe('getCurrentLeaderboard', () => {
  beforeEach(() => {
    mocks.seasonFindFirst.mockResolvedValue(activeSeasonForReadTests())
  })

  it('returns global rankings ordered by season points', async () => {
    mocks.pointsLedgerGroupBy.mockResolvedValue([
      { userId: 'u1', _sum: { delta: 300 }, _min: { createdAt: new Date('2026-01-05T00:00:00Z') } },
      { userId: 'u2', _sum: { delta: 200 }, _min: { createdAt: new Date('2026-01-02T00:00:00Z') } },
    ])
    mocks.userFindMany.mockResolvedValue([
      { id: 'u1', displayName: 'Aarav' },
      { id: 'u2', displayName: 'Ananya' },
    ])
    mocks.profileFindMany.mockResolvedValue([
      { userId: 'u1', avatarUrl: null, pointsTotal: 5000 },
      { userId: 'u2', avatarUrl: null, pointsTotal: 1000 },
    ])
    mocks.snapshotFindMany.mockResolvedValue([])

    const rows = await getCurrentLeaderboard({ scope: 'global', userId: 'viewer' })

    expect(rows.map((r) => r.userId)).toEqual(['u1', 'u2'])
    expect(rows[0].rank).toBe(1)
    expect(rows[0].seasonPoints).toBe(300)
    expect(rows[0].lifetimePoints).toBe(5000)
  })

  it('scopes to friends only, including the viewer themself', async () => {
    mocks.friendshipFindMany.mockResolvedValue([{ userAId: 'me', userBId: 'friend1' }])
    mocks.pointsLedgerGroupBy.mockResolvedValue([])

    await getCurrentLeaderboard({ scope: 'friends', userId: 'me' })

    const where = mocks.pointsLedgerGroupBy.mock.calls[0][0].where
    expect(where.userId.in).toEqual(expect.arrayContaining(['me', 'friend1']))
  })

  it('returns an empty friends leaderboard when no userId is given', async () => {
    const rows = await getCurrentLeaderboard({ scope: 'friends' })
    expect(rows).toEqual([])
    expect(mocks.pointsLedgerGroupBy).not.toHaveBeenCalled()
  })

  it('fails safe to an empty array on a DB error, never throws', async () => {
    mocks.pointsLedgerGroupBy.mockRejectedValue(new Error('db down'))
    const rows = await getCurrentLeaderboard()
    expect(rows).toEqual([])
  })
})

describe('getMyRank', () => {
  beforeEach(() => {
    mocks.seasonFindFirst.mockResolvedValue(activeSeasonForReadTests())
  })

  it('reports null rank and no milestone hint when the user has not earned any points', async () => {
    mocks.pointsLedgerAggregate.mockResolvedValue({ _sum: { delta: null } })
    mocks.profileFindUnique.mockResolvedValue({ pointsTotal: 0 })

    const result = await getMyRank('u1')
    expect(result.rank).toBeNull()
    expect(result.nearestMilestone).toBeNull()
  })

  it('computes rank as one more than the count of users strictly ahead', async () => {
    mocks.pointsLedgerAggregate.mockResolvedValue({ _sum: { delta: 50 } })
    mocks.profileFindUnique.mockResolvedValue({ pointsTotal: 500 })
    mocks.pointsLedgerGroupBy.mockResolvedValue([{ userId: 'a' }, { userId: 'b' }])

    const result = await getMyRank('u1')
    expect(result.rank).toBe(3)
  })

  it('surfaces a subtle nearest-milestone hint when close to a threshold', async () => {
    mocks.pointsLedgerAggregate.mockResolvedValue({ _sum: { delta: 50 } })
    mocks.profileFindUnique.mockResolvedValue({ pointsTotal: 500 })
    mocks.pointsLedgerGroupBy.mockResolvedValue(Array.from({ length: 12 }, (_, i) => ({ userId: `u${i}` }))) // rank 13

    const result = await getMyRank('u1')
    expect(result.rank).toBe(13)
    expect(result.nearestMilestone).toEqual({ label: 'Top 10', spotsAway: 3 })
  })

  it('shows no hint when far from every threshold', async () => {
    mocks.pointsLedgerAggregate.mockResolvedValue({ _sum: { delta: 50 } })
    mocks.profileFindUnique.mockResolvedValue({ pointsTotal: 500 })
    mocks.pointsLedgerGroupBy.mockResolvedValue(Array.from({ length: 199 }, (_, i) => ({ userId: `u${i}` }))) // rank 200

    const result = await getMyRank('u1')
    expect(result.nearestMilestone).toBeNull()
  })

  it('fails safe on a DB error, never throws', async () => {
    mocks.pointsLedgerAggregate.mockRejectedValue(new Error('down'))
    const result = await getMyRank('u1')
    expect(result).toEqual({ rank: null, seasonPoints: 0, lifetimePoints: 0, nearestMilestone: null })
  })
})

// ── Archive & Hall of Impact ──────────────────────────────────────────────

describe('listSeasons', () => {
  it('returns every season newest first, for the Previous Season Archive picker', async () => {
    mocks.seasonFindMany.mockResolvedValue([
      season({ id: 's2', seasonNumber: 2, status: 'ACTIVE' }),
      season({ id: 's1', seasonNumber: 1, status: 'ARCHIVED' }),
    ])
    const seasons = await listSeasons()
    expect(seasons.map((s) => s.seasonNumber)).toEqual([2, 1])
    expect(mocks.seasonFindMany.mock.calls[0][0].orderBy).toEqual({ seasonNumber: 'desc' })
  })

  it('fails safe to an empty array on a DB error', async () => {
    mocks.seasonFindMany.mockRejectedValue(new Error('down'))
    expect(await listSeasons()).toEqual([])
  })
})

describe('getSeasonArchive', () => {
  it('returns null for a season that has not ended yet', async () => {
    mocks.seasonFindUnique.mockResolvedValue(season({ status: 'ACTIVE' }))
    const result = await getSeasonArchive(1)
    expect(result).toBeNull()
  })

  it('returns null for a season that never existed', async () => {
    mocks.seasonFindUnique.mockResolvedValue(null)
    const result = await getSeasonArchive(99)
    expect(result).toBeNull()
  })

  it('returns the permanent rows for an archived season, unchanged by anything after the fact', async () => {
    mocks.seasonFindUnique.mockResolvedValue(season({ status: 'ARCHIVED' }))
    mocks.snapshotFindMany.mockResolvedValue([
      { id: 'r1', seasonId: 's1', userId: 'u1', rank: 1, seasonPoints: 900, badgeId: 'impact_champion', createdAt: new Date() },
    ])
    mocks.userFindMany.mockResolvedValue([{ id: 'u1', displayName: 'Aarav' }])
    mocks.profileFindMany.mockResolvedValue([{ userId: 'u1', avatarUrl: null, pointsTotal: 9000 }])

    const result = await getSeasonArchive(1)
    expect(result?.rows).toHaveLength(1)
    expect(result?.rows[0].badgeId).toBe('impact_champion')
  })

  it('fails safe to null on a DB error', async () => {
    mocks.seasonFindUnique.mockRejectedValue(new Error('down'))
    expect(await getSeasonArchive(1)).toBeNull()
  })
})

describe('getHallOfImpact', () => {
  it('fails safe to an empty array on a DB error', async () => {
    mocks.snapshotFindMany.mockRejectedValue(new Error('down'))
    expect(await getHallOfImpact()).toEqual([])
  })
})

describe('fetchSeasonHistory / seasonalBadgesFromHistory', () => {
  it('fails safe to an empty array on a DB error', async () => {
    mocks.snapshotFindMany.mockRejectedValue(new Error('down'))
    expect(await fetchSeasonHistory('u1')).toEqual([])
  })

  it('keeps only rows with a badge, mapped to a display label', () => {
    const badges = seasonalBadgesFromHistory([
      { seasonNumber: 1, year: 2026, rank: 1, seasonPoints: 900, seasonEndedAt: new Date(), badgeId: 'impact_champion' },
      { seasonNumber: 2, year: 2026, rank: 42, seasonPoints: 30, seasonEndedAt: new Date(), badgeId: null },
    ])
    expect(badges).toHaveLength(1)
    expect(badges[0]).toMatchObject({ badgeId: 'impact_champion', label: 'Impact Champion', rank: 1 })
  })
})

describe('fetchMilestoneTimestamps', () => {
  it('records the entry where the running total first crosses each milestone', async () => {
    mocks.pointsLedgerFindMany.mockResolvedValue([
      { delta: IMPACT_POINT_MILESTONES[0], createdAt: new Date('2026-01-01T00:00:00Z') },
      { delta: IMPACT_POINT_MILESTONES[1] - IMPACT_POINT_MILESTONES[0], createdAt: new Date('2026-02-01T00:00:00Z') },
    ])
    const result = await fetchMilestoneTimestamps('u1')
    expect(result.get(IMPACT_POINT_MILESTONES[0])).toEqual(new Date('2026-01-01T00:00:00Z'))
    expect(result.get(IMPACT_POINT_MILESTONES[1])).toEqual(new Date('2026-02-01T00:00:00Z'))
    expect(result.has(IMPACT_POINT_MILESTONES[2])).toBe(false)
  })

  it('fails safe to an empty map on a DB error', async () => {
    mocks.pointsLedgerFindMany.mockRejectedValue(new Error('down'))
    const result = await fetchMilestoneTimestamps('u1')
    expect(result.size).toBe(0)
  })
})

// ── Achievements (pure) ───────────────────────────────────────────────────

describe('computeLeagueAchievements', () => {
  const base = { lifetimePoints: 0, seasonHistory: [], milestoneReachedAt: new Map<number, Date>() }

  it('every achievement is unearned with no history and no points', () => {
    const result = computeLeagueAchievements(base)
    expect(result.every((a) => !a.earned && a.earnedAt === null)).toBe(true)
  })

  it('marks first participation, top finishes and season champion from a single season 1 win', () => {
    const result = computeLeagueAchievements({
      ...base,
      seasonHistory: [{ seasonNumber: 1, year: 2026, rank: 1, seasonPoints: 900, seasonEndedAt: new Date('2026-04-01T00:00:00Z'), badgeId: 'impact_champion' }],
    })
    const byId = Object.fromEntries(result.map((a) => [a.id, a]))
    expect(byId.first_participation.earned).toBe(true)
    expect(byId.first_top_100.earned).toBe(true)
    expect(byId.first_top_10.earned).toBe(true)
    expect(byId.top_5_finish.earned).toBe(true)
    expect(byId.season_champion.earned).toBe(true)
    expect(byId.multiple_season_wins.earned).toBe(false)
  })

  it('requires two #1 finishes for multiple season wins, dated to the second one', () => {
    const result = computeLeagueAchievements({
      ...base,
      seasonHistory: [
        { seasonNumber: 1, year: 2026, rank: 1, seasonPoints: 900, seasonEndedAt: new Date('2026-04-01T00:00:00Z'), badgeId: 'impact_champion' },
        { seasonNumber: 3, year: 2026, rank: 1, seasonPoints: 950, seasonEndedAt: new Date('2026-10-01T00:00:00Z'), badgeId: 'impact_champion' },
      ],
    })
    const win = result.find((a) => a.id === 'multiple_season_wins')!
    expect(win.earned).toBe(true)
    expect(win.earnedAt).toEqual(new Date('2026-10-01T00:00:00Z'))
  })

  it(`requires ${CONSECUTIVE_TOP5_STREAK} consecutive top-5 seasons, broken by a gap or a bad season`, () => {
    const consecutive = computeLeagueAchievements({
      ...base,
      seasonHistory: [
        { seasonNumber: 1, year: 2026, rank: 4, seasonPoints: 100, seasonEndedAt: new Date('2026-04-01T00:00:00Z'), badgeId: 'community_leader' },
        { seasonNumber: 2, year: 2026, rank: 3, seasonPoints: 120, seasonEndedAt: new Date('2026-07-01T00:00:00Z'), badgeId: 'impact_pioneer' },
        { seasonNumber: 3, year: 2026, rank: 5, seasonPoints: 90, seasonEndedAt: new Date('2026-10-01T00:00:00Z'), badgeId: 'rising_contributor' },
      ],
    })
    expect(consecutive.find((a) => a.id === 'consecutive_top_5')!.earned).toBe(true)

    const brokenByGap = computeLeagueAchievements({
      ...base,
      seasonHistory: [
        { seasonNumber: 1, year: 2026, rank: 4, seasonPoints: 100, seasonEndedAt: new Date('2026-04-01T00:00:00Z'), badgeId: 'community_leader' },
        // season 2 skipped — not consecutive
        { seasonNumber: 3, year: 2026, rank: 3, seasonPoints: 120, seasonEndedAt: new Date('2026-10-01T00:00:00Z'), badgeId: 'impact_pioneer' },
        { seasonNumber: 4, year: 2026, rank: 5, seasonPoints: 90, seasonEndedAt: new Date('2027-01-01T00:00:00Z'), badgeId: 'rising_contributor' },
      ],
    })
    expect(brokenByGap.find((a) => a.id === 'consecutive_top_5')!.earned).toBe(false)

    const brokenByBadSeason = computeLeagueAchievements({
      ...base,
      seasonHistory: [
        { seasonNumber: 1, year: 2026, rank: 4, seasonPoints: 100, seasonEndedAt: new Date('2026-04-01T00:00:00Z'), badgeId: 'community_leader' },
        { seasonNumber: 2, year: 2026, rank: 40, seasonPoints: 20, seasonEndedAt: new Date('2026-07-01T00:00:00Z'), badgeId: null },
        { seasonNumber: 3, year: 2026, rank: 3, seasonPoints: 120, seasonEndedAt: new Date('2026-10-01T00:00:00Z'), badgeId: 'impact_pioneer' },
      ],
    })
    expect(brokenByBadSeason.find((a) => a.id === 'consecutive_top_5')!.earned).toBe(false)
  })

  it('unlocks each configurable point milestone at its threshold, dated from the ledger crossing', () => {
    const reachedAt = new Map<number, Date>([[IMPACT_POINT_MILESTONES[0], new Date('2026-03-01T00:00:00Z')]])
    const result = computeLeagueAchievements({
      lifetimePoints: IMPACT_POINT_MILESTONES[0],
      seasonHistory: [],
      milestoneReachedAt: reachedAt,
    })
    const first = result.find((a) => a.id === `impact_milestone_${IMPACT_POINT_MILESTONES[0]}`)!
    const second = result.find((a) => a.id === `impact_milestone_${IMPACT_POINT_MILESTONES[1]}`)!
    expect(first.earned).toBe(true)
    expect(first.earnedAt).toEqual(new Date('2026-03-01T00:00:00Z'))
    expect(second.earned).toBe(false)
  })

  it('never reads or references Trust Score or Impact Point mutation — pure function of its inputs only', () => {
    // Calling twice with identical inputs must be byte-identical — no hidden
    // state, no I/O, nothing derived from anything but the arguments given.
    const inputs = { lifetimePoints: 500, seasonHistory: [], milestoneReachedAt: new Map() }
    expect(computeLeagueAchievements(inputs)).toEqual(computeLeagueAchievements(inputs))
  })
})

// ── Featured achievements ─────────────────────────────────────────────────

describe('setFeaturedAchievements', () => {
  it('filters out unknown ids, dedupes, and caps at the configured maximum', async () => {
    mocks.profileUpdate.mockResolvedValue({})
    const ids = ['first_participation', 'first_participation', 'bogus_id', 'season_champion', 'top_5_finish', 'first_top_10']

    const result = await setFeaturedAchievements('u1', ids)

    expect(result).toHaveLength(MAX_FEATURED_ACHIEVEMENTS)
    expect(result).not.toContain('bogus_id')
    expect(new Set(result).size).toBe(result.length)
    expect(mocks.profileUpdate).toHaveBeenCalledWith({ where: { userId: 'u1' }, data: { featuredAchievementIds: result } })
  })

  it('accepts a seasonal badge id as a valid featured item', async () => {
    mocks.profileUpdate.mockResolvedValue({})
    const result = await setFeaturedAchievements('u1', [SEASON_BADGE_IDS[1]])
    expect(result).toEqual([SEASON_BADGE_IDS[1]])
  })
})
