import { Router, type IRouter } from 'express'
import { prisma } from '../../lib/prisma'
import { authenticate, type AuthedRequest } from '../../middleware/authenticate'
import { badRequest } from '../../lib/http-error'
import {
  ensureCurrentSeason,
  getCurrentLeaderboard,
  getMyRank,
  listSeasons,
  getSeasonArchive,
  getHallOfImpact,
  fetchSeasonHistory,
  fetchMilestoneTimestamps,
  seasonalBadgesFromHistory,
  computeLeagueAchievements,
  setFeaturedAchievements,
} from '../../lib/impact-league'

export const leagueRouter: IRouter = Router()

// ─── GET /league/season — current season boundaries ─────────────────────

leagueRouter.get('/season', authenticate, async (_req, res, next) => {
  try {
    res.json(await ensureCurrentSeason())
  } catch (err) { next(err) }
})

// ─── GET /league/leaderboard?scope=global|friends — live current season ──

leagueRouter.get('/leaderboard', authenticate, async (req, res, next) => {
  const userId = (req as AuthedRequest).userId!
  const scope = req.query.scope === 'friends' ? 'friends' : 'global'
  const takeRaw = typeof req.query.take === 'string' ? Number(req.query.take) : undefined
  const take = Number.isFinite(takeRaw) && takeRaw! > 0 ? takeRaw : undefined

  try {
    const rows = await getCurrentLeaderboard({ scope, userId, take })
    res.json({ scope, rows })
  } catch (err) { next(err) }
})

// ─── GET /league/me — my current rank + motivation hint ─────────────────

leagueRouter.get('/me', authenticate, async (req, res, next) => {
  const userId = (req as AuthedRequest).userId!
  try {
    res.json(await getMyRank(userId))
  } catch (err) { next(err) }
})

// ─── GET /league/seasons — every season, newest first ────────────────────

leagueRouter.get('/seasons', authenticate, async (_req, res, next) => {
  try {
    res.json({ seasons: await listSeasons() })
  } catch (err) { next(err) }
})

// ─── GET /league/archive/:seasonNumber — a past season's final leaderboard ─

leagueRouter.get('/archive/:seasonNumber', authenticate, async (req, res, next) => {
  const seasonNumber = Number(req.params.seasonNumber)
  if (!Number.isInteger(seasonNumber) || seasonNumber < 1) {
    return next(badRequest('Invalid season number', 'INVALID_SEASON_NUMBER'))
  }
  try {
    const archive = await getSeasonArchive(seasonNumber)
    if (!archive) return res.json({ season: null, rows: [] })
    res.json(archive)
  } catch (err) { next(err) }
})

// ─── GET /league/hall-of-impact — permanent top-5 archive, every season ──

leagueRouter.get('/hall-of-impact', authenticate, async (_req, res, next) => {
  try {
    res.json({ entries: await getHallOfImpact() })
  } catch (err) { next(err) }
})

// ─── GET /league/achievements/:userId — badges + milestone achievements ──

leagueRouter.get('/achievements/:userId', authenticate, async (req, res, next) => {
  const targetUserId = req.params.userId
  try {
    const [profile, history] = await Promise.all([
      prisma.profile.findUnique({ where: { userId: targetUserId }, select: { pointsTotal: true, featuredAchievementIds: true } }),
      fetchSeasonHistory(targetUserId),
    ])
    const milestoneReachedAt = await fetchMilestoneTimestamps(targetUserId)
    const achievements = computeLeagueAchievements({
      lifetimePoints: profile?.pointsTotal ?? 0,
      seasonHistory: history,
      milestoneReachedAt,
    })
    res.json({
      seasonalBadges: seasonalBadgesFromHistory(history),
      achievements,
      featuredAchievementIds: profile?.featuredAchievementIds ?? [],
    })
  } catch (err) { next(err) }
})

// ─── PATCH /league/featured — choose which achievements to showcase ─────

leagueRouter.patch('/featured', authenticate, async (req, res, next) => {
  const userId = (req as AuthedRequest).userId!
  const ids = req.body?.achievementIds
  if (!Array.isArray(ids) || !ids.every((id) => typeof id === 'string')) {
    return next(badRequest('achievementIds must be an array of strings', 'INVALID_BODY'))
  }
  try {
    const featuredAchievementIds = await setFeaturedAchievements(userId, ids)
    res.json({ featuredAchievementIds })
  } catch (err) { next(err) }
})
