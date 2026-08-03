// plus-analytics.ts imports lib/prisma at module load time (for
// recordEngagement, unused by these pure-function tests), which needs
// DATABASE_URL present for the import itself to succeed — same convention
// as needs/__tests__/scoreNeed.test.ts.
import 'dotenv/config'
import { describe, it, expect } from 'vitest'
import { computePlusAnalytics, resolveWindow, actorKeyFor, type EngagementRow } from '../plus-analytics'

describe('actorKeyFor', () => {
  it('is deterministic for the same ip+userAgent', () => {
    expect(actorKeyFor('1.2.3.4', 'ua')).toBe(actorKeyFor('1.2.3.4', 'ua'))
  })

  it('differs for different ips', () => {
    expect(actorKeyFor('1.2.3.4', 'ua')).not.toBe(actorKeyFor('5.6.7.8', 'ua'))
  })
})

describe('resolveWindow', () => {
  it('defaults to 7 days for anything other than 30d', () => {
    expect(resolveWindow('7d').windowDays).toBe(7)
  })
  it('honors 30d', () => {
    expect(resolveWindow('30d').windowDays).toBe(30)
  })
})

const window = resolveWindow('7d')

function row(kind: EngagementRow['kind'], targetType: EngagementRow['targetType'], targetId: string, day: string): EngagementRow {
  return { kind, targetType, targetId, day }
}

describe('computePlusAnalytics', () => {
  it('counts profile and need views separately, and needViewsByNeedId per need', () => {
    const rows = [
      row('VIEW', 'PROFILE', 'me', '2026-06-10'),
      row('VIEW', 'PROFILE', 'me', '2026-06-11'),
      row('VIEW', 'NEED', 'n1', '2026-06-10'),
      row('VIEW', 'NEED', 'n1', '2026-06-11'),
      row('VIEW', 'NEED', 'n2', '2026-06-11'),
    ]
    const result = computePlusAnalytics(
      rows, { postedInWindow: 0, postedWithAtLeastOneOffer: 0 },
      { offersReceived: 0, reviewsReceived: 0, vouchesReceived: 0 }, 0, window, [],
    )
    expect(result.profileViews).toBe(2)
    expect(result.needViews).toBe(3)
    expect(result.needViewsByNeedId).toEqual({ n1: 2, n2: 1 })
  })

  it('counts SHARE rows separately from VIEW rows', () => {
    const rows = [row('SHARE', 'NEED', 'n1', '2026-06-10'), row('VIEW', 'NEED', 'n1', '2026-06-10')]
    const result = computePlusAnalytics(
      rows, { postedInWindow: 0, postedWithAtLeastOneOffer: 0 },
      { offersReceived: 0, reviewsReceived: 0, vouchesReceived: 0 }, 0, window, [],
    )
    expect(result.shares).toBe(1)
    expect(result.needViews).toBe(1)
  })

  it('response rate is null (never 0) when no needs were posted in the window', () => {
    const result = computePlusAnalytics(
      [], { postedInWindow: 0, postedWithAtLeastOneOffer: 0 },
      { offersReceived: 0, reviewsReceived: 0, vouchesReceived: 0 }, 0, window, [],
    )
    expect(result.responseRate).toBeNull()
  })

  it('response rate is the fraction of posted needs with at least one offer', () => {
    const result = computePlusAnalytics(
      [], { postedInWindow: 4, postedWithAtLeastOneOffer: 3 },
      { offersReceived: 0, reviewsReceived: 0, vouchesReceived: 0 }, 0, window, [],
    )
    expect(result.responseRate).toBe(0.75)
  })

  it('trend is insufficientData under 14 days of history, never a fabricated direction', () => {
    const tenDays = Array.from({ length: 10 }, (_, i) => ({ day: `2026-06-0${i + 1}`, count: 5 }))
    const result = computePlusAnalytics(
      [], { postedInWindow: 0, postedWithAtLeastOneOffer: 0 },
      { offersReceived: 0, reviewsReceived: 0, vouchesReceived: 0 }, 0, window, tenDays,
    )
    expect(result.trend.insufficientData).toBe(true)
    expect(result.trend.direction).toBeNull()
  })

  it('trend direction compares the last 7 days against the prior 7, once 14+ days exist', () => {
    const days = [
      ...Array.from({ length: 7 }, (_, i) => ({ day: `2026-05-2${i}`, count: 2 })), // prev 7 = 14
      ...Array.from({ length: 7 }, (_, i) => ({ day: `2026-06-0${i}`, count: 4 })), // last 7 = 28
    ]
    const result = computePlusAnalytics(
      [], { postedInWindow: 0, postedWithAtLeastOneOffer: 0 },
      { offersReceived: 0, reviewsReceived: 0, vouchesReceived: 0 }, 0, window, days,
    )
    expect(result.trend.insufficientData).toBe(false)
    expect(result.trend.direction).toBeCloseTo((28 - 14) / 14, 5)
  })

  it('passes through the pre-computed engagement counts and reach untouched', () => {
    const result = computePlusAnalytics(
      [], { postedInWindow: 0, postedWithAtLeastOneOffer: 0 },
      { offersReceived: 3, reviewsReceived: 2, vouchesReceived: 1 }, 42, window, [],
    )
    expect(result.engagement).toEqual({ offersReceived: 3, reviewsReceived: 2, vouchesReceived: 1 })
    expect(result.reach).toBe(42)
  })
})
