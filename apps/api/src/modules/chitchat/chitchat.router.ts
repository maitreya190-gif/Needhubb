import { Router, type IRouter } from 'express'
import { z } from 'zod'
import { prisma } from '../../lib/prisma'
import { authenticate, type AuthedRequest } from '../../middleware/authenticate'
import { badRequest, notFound } from '../../lib/http-error'
import { isBlockedBetween } from '../friends/friends.service'
import { CHITCHAT_BOOST_TIERS, fetchActiveChitchatBoosts } from '../../lib/visibility-boost'

export const chitchatRouter: IRouter = Router()

chitchatRouter.use(authenticate)

const availabilityBody = z.object({ hours: z.number().min(1).max(12) })

// POST /chitchat/availability — set availability window
chitchatRouter.post('/availability', async (req, res, next) => {
  try {
    const me = (req as AuthedRequest).userId!
    const parsed = availabilityBody.safeParse(req.body)
    if (!parsed.success) return next(badRequest('hours must be 1..12', 'INVALID_BODY'))

    const until = new Date(Date.now() + parsed.data.hours * 60 * 60 * 1000)
    await prisma.profile.upsert({
      where: { userId: me },
      update: { chitchatAvailableUntil: until },
      create: { userId: me, chitchatAvailableUntil: until },
    })
    res.json({ availableUntil: until.toISOString() })
  } catch (err) { next(err) }
})

// DELETE /chitchat/availability — clear
chitchatRouter.delete('/availability', async (req, res, next) => {
  try {
    const me = (req as AuthedRequest).userId!
    await prisma.profile.updateMany({
      where: { userId: me },
      data: { chitchatAvailableUntil: null },
    })
    res.json({ ok: true })
  } catch (err) { next(err) }
})

// GET /chitchat/status — my current availability
chitchatRouter.get('/status', async (req, res, next) => {
  try {
    const me = (req as AuthedRequest).userId!
    const p = await prisma.profile.findUnique({
      where: { userId: me },
      select: { chitchatAvailableUntil: true },
    })
    const until = p?.chitchatAvailableUntil
    const available = until ? until.getTime() > Date.now() : false
    res.json({ available, availableUntil: until?.toISOString() ?? null })
  } catch (err) { next(err) }
})

// ── Visibility boost — spend Impact Points to appear first in ChitChat ──────
// Body: { "tier": "3h" | "6h" | "12h" }. Same shape as the existing
// POST /needs/:id/boost (see needs.router.ts): verify affordability, debit
// PointsLedger + Profile in one transaction, create a VisibilityBoost.
// Reuses the VisibilityBoost model's existing (until now unused) PROFILE
// target type — no schema change.

chitchatRouter.post('/boost', async (req, res, next) => {
  const userId = (req as AuthedRequest).userId!
  const tier = (req.body?.tier as string | undefined)?.toLowerCase()

  if (!tier || !CHITCHAT_BOOST_TIERS[tier]) {
    return next(badRequest('tier must be "3h", "6h", or "12h"', 'INVALID_TIER'))
  }
  const { hours, cost } = CHITCHAT_BOOST_TIERS[tier]

  try {
    const existingBoost = await prisma.visibilityBoost.findFirst({
      where: { targetId: userId, targetType: 'PROFILE', expiresAt: { gt: new Date() } },
    })
    if (existingBoost) {
      return next(badRequest(
        `Your Chit-Chat visibility is already boosted until ${existingBoost.expiresAt.toISOString()}`,
        'ALREADY_BOOSTED',
      ))
    }

    const profile = await prisma.profile.findUnique({ where: { userId } })
    if (!profile) return next(notFound('Profile not found'))
    if (profile.pointsTotal < cost) {
      return next(badRequest(
        `Not enough Impact Points. You have ${profile.pointsTotal} pts but need ${cost} pts.`,
        'INSUFFICIENT_POINTS',
      ))
    }

    const expiresAt = new Date(Date.now() + hours * 60 * 60 * 1000)
    const [boost] = await prisma.$transaction([
      prisma.visibilityBoost.create({
        data: { userId, targetType: 'PROFILE', targetId: userId, expiresAt },
      }),
      prisma.profile.update({
        where: { userId },
        data: { pointsTotal: { decrement: cost } },
      }),
      prisma.pointsLedger.create({
        data: { userId, delta: -cost, reason: `Boost Chit-Chat visibility for ${hours}h`, refId: userId },
      }),
    ])

    res.json({
      ok: true,
      boost: { id: boost.id, expiresAt: boost.expiresAt, tier, cost },
      newBalance: profile.pointsTotal - cost,
    })
  } catch (err) { next(err) }
})

// GET /chitchat/boost — check my active boost status
chitchatRouter.get('/boost', async (req, res, next) => {
  const userId = (req as AuthedRequest).userId!
  try {
    const boost = await prisma.visibilityBoost.findFirst({
      where: { targetId: userId, targetType: 'PROFILE', expiresAt: { gt: new Date() } },
    })
    res.json({ boosted: !!boost, expiresAt: boost?.expiresAt ?? null })
  } catch (err) { next(err) }
})

// GET /chitchat/available-people — active users, sorted by proximity to caller.
// Query params: lat, lng, distanceKm (optional cap).
// If caller's coords are missing from query, we fall back to their stored
// profile.lat/lng. If still unavailable, return unsorted.
chitchatRouter.get('/available-people', async (req, res, next) => {
  try {
    const me = (req as AuthedRequest).userId!
    const now = new Date()

    const qLat = req.query.lat != null ? Number(req.query.lat) : null
    const qLng = req.query.lng != null ? Number(req.query.lng) : null
    const distanceKm = req.query.distanceKm != null ? Number(req.query.distanceKm) : null

    // Fetch caller's stored coords as fallback + blocks in both directions.
    const [meProfile, blocksOut, blocksIn] = await Promise.all([
      prisma.profile.findUnique({
        where: { userId: me }, select: { lat: true, lng: true },
      }),
      prisma.block.findMany({ where: { blockerId: me }, select: { blockedId: true } }),
      prisma.block.findMany({ where: { blockedId: me }, select: { blockerId: true } }),
    ])
    const excluded = new Set<string>([me])
    blocksOut.forEach((b) => excluded.add(b.blockedId))
    blocksIn.forEach((b) => excluded.add(b.blockerId))

    const myLat = Number.isFinite(qLat) && qLat != null ? qLat : meProfile?.lat ?? null
    const myLng = Number.isFinite(qLng) && qLng != null ? qLng : meProfile?.lng ?? null

    const rows = await prisma.profile.findMany({
      where: {
        chitchatAvailableUntil: { gt: now },
        userId: { notIn: Array.from(excluded) },
      },
      select: {
        userId: true,
        avatarUrl: true,
        bio: true,
        lat: true,
        lng: true,
        chitchatAvailableUntil: true,
        user: { select: { displayName: true } },
      },
    })

    // Score by proximity; drop rows outside distanceKm (when both sides know location).
    type Ranked = { row: (typeof rows)[number]; distanceKm: number | null }
    const ranked: Ranked[] = []
    for (const r of rows) {
      let d: number | null = null
      if (myLat != null && myLng != null && r.lat != null && r.lng != null) {
        d = haversineKm(myLat, myLng, r.lat, r.lng)
        if (distanceKm != null && d > distanceKm) continue
      }
      ranked.push({ row: r, distanceKm: d })
    }

    // Nearest first. Rows with no coords fall to the bottom (Infinity).
    ranked.sort((a, b) =>
      (a.distanceKm ?? Infinity) - (b.distanceKm ?? Infinity))

    // Paid visibility boost: reorders the list (boosted users first, each
    // group still nearest-first among itself) without touching the
    // distanceKm shown — it changes *placement*, never what's reported to
    // the viewer, so this can't be used to misrepresent someone's location.
    const activeBoosts = await fetchActiveChitchatBoosts(ranked.map((r) => r.row.userId))
    if (activeBoosts.size > 0) {
      ranked.sort((a, b) => {
        const aBoosted = activeBoosts.has(a.row.userId) ? 1 : 0
        const bBoosted = activeBoosts.has(b.row.userId) ? 1 : 0
        if (aBoosted !== bBoosted) return bBoosted - aBoosted
        return (a.distanceKm ?? Infinity) - (b.distanceKm ?? Infinity)
      })
    }

    res.json(ranked.map(({ row, distanceKm }) => ({
      userId: row.userId,
      displayName: row.user.displayName,
      avatarUrl: row.avatarUrl,
      bio: row.bio,
      availableUntil: row.chitchatAvailableUntil?.toISOString(),
      lat: row.lat,
      lng: row.lng,
      distanceKm: distanceKm != null ? Math.round(distanceKm * 10) / 10 : null,
      boosted: activeBoosts.has(row.userId),
    })))
  } catch (err) { next(err) }
})

function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371
  const toRad = (deg: number) => (deg * Math.PI) / 180
  const dLat = toRad(lat2 - lat1)
  const dLng = toRad(lng2 - lng1)
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2
  return 2 * R * Math.asin(Math.sqrt(a))
}
