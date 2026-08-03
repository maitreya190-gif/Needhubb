/**
 * NeedHub Plus analytics: honest metrics computed only from data that
 * actually exists, with no invented numbers and no backfill. Every metric
 * below is deliberately labeled for exactly what it measures — see the
 * per-metric notes. Things that cannot be honestly computed (ad-style feed
 * impressions, confirmed share sends, viewer demographics) are not offered.
 *
 * Write path (recordEngagement) is a fire-and-forget dedupe-by-day insert;
 * read path (computePlusAnalytics) is a pure function over already-fetched
 * rows, so the math is unit-testable without touching Prisma.
 */

import crypto from 'node:crypto'
import { prisma } from './prisma'

const DAILY_SALT = process.env.ANALYTICS_DAILY_SALT || 'needhub-analytics-salt'

function dayString(d: Date = new Date()): string {
  return d.toISOString().slice(0, 10) // 'YYYY-MM-DD', UTC
}

/**
 * IP + user-agent derived, NEVER the JWT subject — tryGetUserId is an
 * unverified decode (see needs.router.ts), fine for the existing block
 * filter, wrong to key a view-dedupe metric on since it's trivially
 * spoofable by forging a Bearer header.
 */
export function actorKeyFor(ip: string, userAgent: string): string {
  return crypto.createHash('sha256').update(`${ip}|${userAgent}|${DAILY_SALT}`).digest('hex').slice(0, 24)
}

export type EngagementKind = 'VIEW' | 'SHARE'
export type EngagementTargetType = 'PROFILE' | 'NEED'

/**
 * Fire-and-forget. Never throws, never awaited on a response path — an
 * analytics write failing must never affect the need/profile view it's
 * attached to. createMany+skipDuplicates makes the daily-unique-viewer
 * dedupe a plain insert with no read-then-write race.
 */
export async function recordEngagement(args: {
  kind: EngagementKind
  targetType: EngagementTargetType
  targetId: string
  ownerId: string
  ip: string
  userAgent: string
  actorUserId?: string | null
}): Promise<void> {
  // Self-views/self-shares don't count — a poster opening their own need
  // isn't "reach".
  if (args.actorUserId && args.actorUserId === args.ownerId) return
  try {
    await prisma.contentEngagementDaily.createMany({
      data: [{
        kind: args.kind,
        targetType: args.targetType,
        targetId: args.targetId,
        ownerId: args.ownerId,
        actorKey: actorKeyFor(args.ip, args.userAgent),
        actorUserId: args.actorUserId ?? null,
        day: dayString(),
      }],
      skipDuplicates: true,
    })
  } catch (err) {
    console.error('[plus-analytics] failed to record engagement', err)
  }
}

export interface PlusAnalyticsWindow {
  windowDays: number
  since: Date
}

export function resolveWindow(window: '7d' | '30d'): PlusAnalyticsWindow {
  const windowDays = window === '30d' ? 30 : 7
  return { windowDays, since: new Date(Date.now() - windowDays * 24 * 3_600_000) }
}

export interface EngagementRow {
  kind: EngagementKind
  targetType: EngagementTargetType
  targetId: string
  day: string
}

export interface NeedStatsInput {
  /** One entry per need the user posted, regardless of window — needed to
   * compute response rate over needs created in-window. */
  postedInWindow: number
  postedWithAtLeastOneOffer: number
}

export interface PlusAnalytics {
  windowDays: number
  profileViews: number
  needViews: number
  needViewsByNeedId: Record<string, number>
  reach: number
  shares: number
  engagement: { offersReceived: number; reviewsReceived: number; vouchesReceived: number }
  responseRate: number | null
  trend: {
    dailyViews: { day: string; count: number }[]
    direction: number | null
    insufficientData: boolean
  }
}

/**
 * Pure aggregation — the router fetches `rows` (ContentEngagementDaily for
 * this owner) and the small set of pre-computed counts, this function does
 * only arithmetic. Kept separate so the honesty properties (null instead of
 * 0, insufficientData instead of a fake trend) are directly unit-testable.
 */
export function computePlusAnalytics(
  rows: EngagementRow[],
  needStats: NeedStatsInput,
  engagementCounts: { offersReceived: number; reviewsReceived: number; vouchesReceived: number },
  reachActorCount: number,
  window: PlusAnalyticsWindow,
  allDailyViewCounts: { day: string; count: number }[],
): PlusAnalytics {
  const profileViews = rows.filter((r) => r.kind === 'VIEW' && r.targetType === 'PROFILE').length
  const needViewRows = rows.filter((r) => r.kind === 'VIEW' && r.targetType === 'NEED')
  const needViews = needViewRows.length
  const needViewsByNeedId: Record<string, number> = {}
  for (const r of needViewRows) {
    needViewsByNeedId[r.targetId] = (needViewsByNeedId[r.targetId] ?? 0) + 1
  }
  const shares = rows.filter((r) => r.kind === 'SHARE').length

  const responseRate = needStats.postedInWindow > 0
    ? needStats.postedWithAtLeastOneOffer / needStats.postedInWindow
    : null

  // Trend needs 14 days of history to compare two full 7-day windows —
  // otherwise "direction" would be comparing a full week against a partial
  // one, which is not a trend, it's noise dressed up as a trend.
  const sorted = [...allDailyViewCounts].sort((a, b) => a.day.localeCompare(b.day))
  const insufficientData = sorted.length < 14
  let direction: number | null = null
  if (!insufficientData) {
    const last7 = sorted.slice(-7).reduce((s, d) => s + d.count, 0)
    const prev7 = sorted.slice(-14, -7).reduce((s, d) => s + d.count, 0)
    direction = prev7 > 0 ? (last7 - prev7) / prev7 : (last7 > 0 ? 1 : 0)
  }

  return {
    windowDays: window.windowDays,
    profileViews,
    needViews,
    needViewsByNeedId,
    reach: reachActorCount,
    shares,
    engagement: engagementCounts,
    responseRate,
    trend: { dailyViews: sorted, direction, insufficientData },
  }
}
