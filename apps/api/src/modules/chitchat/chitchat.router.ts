import { Router, type IRouter } from 'express'
import { z } from 'zod'
import { prisma } from '../../lib/prisma'
import { authenticate, type AuthedRequest } from '../../middleware/authenticate'
import { badRequest } from '../../lib/http-error'
import { isBlockedBetween } from '../friends/friends.service'

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

    res.json(ranked.map(({ row, distanceKm }) => ({
      userId: row.userId,
      displayName: row.user.displayName,
      avatarUrl: row.avatarUrl,
      bio: row.bio,
      availableUntil: row.chitchatAvailableUntil?.toISOString(),
      lat: row.lat,
      lng: row.lng,
      distanceKm: distanceKm != null ? Math.round(distanceKm * 10) / 10 : null,
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
