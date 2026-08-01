import { Router, type IRouter } from 'express'
import { z } from 'zod'
import multer from 'multer'
import { Prisma, type NeedType, type EarnCategory, type ConnectCategory, type ReportTargetType } from '@prisma/client'
import { prisma } from '../../lib/prisma'
import { checkText } from '../../lib/moderation'
import { decomposeNeed } from '../../lib/llm'
import {
  embedBatch, cosineSimilarity, needSignalText, userSignalText, embeddingsAvailable,
} from '../../lib/embeddings'
import { pushNotification } from '../../lib/notifications'
import { notifyMatchingSkillUsers } from '../../lib/skill-matching'
import { getIo, emitToUser } from '../../lib/socket'
import { getSystemUserId } from '../../lib/system-user'
import { computeTrustScore } from '../../lib/trust-score'
import { authenticate, type AuthedRequest } from '../../middleware/authenticate'
import { isBlockedBetween } from '../friends/friends.service'
import {
  badRequest, forbidden, notFound, unprocessable,
} from '../../lib/http-error'
import { suggestResponse } from '../../lib/lyzr'
import {
  decomposeBody, createNeedBody, feedQuery, respondBody, editResponseBody, respondDecisionBody, statusBody,
} from './needs.schemas'
import { uploadFile, storageKey } from '../../lib/storage'

export const needsRouter: IRouter = Router()
const RESPONSE_EDIT_WINDOW_MS = 10 * 60 * 1000

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (!file.mimetype.startsWith('image/')) cb(new Error('Images only'))
    else cb(null, true)
  },
})

// ─── POST /needs/decompose — the signature endpoint ──────────────────────────

needsRouter.post('/decompose', authenticate, async (req, res, next) => {
  const parsed = decomposeBody.safeParse(req.body)
  if (!parsed.success) return next(badRequest('Invalid decompose payload', 'INVALID_BODY'))
  const userId = (req as AuthedRequest).userId
  const { text } = parsed.data

  try {
    const verdict = await checkText(text)

    if (verdict.hardBlocked || verdict.softFlag) {
      const source = verdict.hardBlocked ? 'moderation_hard' : 'moderation_soft'
      // Fire-and-forget — a DB failure here must never turn a block into a 500.
      getSystemUserId().then((reporterId) => autoReport({
        reporterId,
        targetType: 'NEED',
        targetId: `pending:${userId}`,
        reason: verdict.hardBlocked
          ? `Auto-blocked: ${verdict.reasons.join(', ')}`
          : `Soft-flagged by AI: score ${verdict.llmScore?.toFixed(2)}`,
        source,
        detail: { matches: verdict.matches, reasons: verdict.reasons, score: verdict.llmScore, byUserId: userId, text },
      })).catch((e) => console.error('[moderation] autoReport failed:', e.message))
      return next(unprocessable('Profanity or harmful content detected. Please revise your post.', 'MODERATION_BLOCKED'))
    }

    let result
    try {
      result = await decomposeNeed(text)
    } catch (err) {
      // Fall back to a single need using the raw text — the user's post never fails
      // just because Grok/Groq/OpenAI is down.
      console.warn('[decompose] LLM fallback:', (err as Error).message)
      result = {
        needs: [{
          title: text.slice(0, 60),
          description: text,
          needType: 'EARN' as const,
          earnCategory: 'OTHER' as const,
          connectCategory: null,
          budgetMin: null,
          budgetMax: null,
          deadline: null,
        }],
      }
    }

    res.json({ needs: result.needs, softFlagged: verdict.softFlag })
  } catch (err) { next(err) }
})

// ─── POST /needs — create needs (parent + sub-needs) ─────────────────────────

needsRouter.post('/', authenticate, async (req, res, next) => {
  const parsed = createNeedBody.safeParse(req.body)
  if (!parsed.success) return next(badRequest('Invalid create-need payload', 'INVALID_BODY'))
  const userId = (req as AuthedRequest).userId
  const { needs } = parsed.data

  try {
    // Moderation on the concatenated text of every need. One block cancels the whole post.
    const combined = needs.map((n) => `${n.title} ${n.description}`).join(' \n ')
    const verdict = await checkText(combined)
    if (verdict.hardBlocked || verdict.softFlag) {
      const source = verdict.hardBlocked ? 'moderation_hard' : 'moderation_soft'
      await autoReport({
        reporterId: await getSystemUserId(),
        targetType: 'NEED',
        targetId: `pending:${userId}`,
        reason: verdict.hardBlocked
          ? `Auto-blocked at create: ${verdict.reasons.join(', ')}`
          : `Soft-flagged at create: score ${verdict.llmScore?.toFixed(2)}`,
        source,
        detail: { matches: verdict.matches, score: verdict.llmScore, byUserId: userId, text: combined },
      })
      return next(unprocessable('Content violates community guidelines', 'MODERATION_BLOCKED'))
    }

    // Check before tx — if this is the user's first need, activate any pending referral
    const priorNeedCount = await prisma.need.count({ where: { posterId: userId } })
    const isFirstNeed = priorNeedCount === 0

    const created = await prisma.$transaction(async (tx) => {
      const profile = await tx.profile.findUnique({
        where: { userId },
        select: { lat: true, lng: true, locationText: true },
      })
      const defaultLat = profile?.lat ?? null
      const defaultLng = profile?.lng ?? null
      const defaultLoc = profile?.locationText ?? null

      const [first, ...rest] = needs
      const parent = await tx.need.create({
        data: {
          posterId: userId,
          title: first.title,
          description: first.description,
          needType: first.needType as NeedType,
          earnCategory: first.earnCategory as EarnCategory | null,
          connectCategory: first.connectCategory as ConnectCategory | null,
          budgetMin: first.budgetMin,
          budgetMax: first.budgetMax,
          deadline: first.deadline ? new Date(first.deadline) : null,
          locationText: first.locationText ?? defaultLoc,
          lat: first.lat ?? defaultLat,
          lng: first.lng ?? defaultLng,
          isPaid: first.budgetMin != null || first.budgetMax != null,
        },
      })

      const subs = await Promise.all(rest.map((n) =>
        tx.need.create({
          data: {
            posterId: userId,
            title: n.title,
            description: n.description,
            needType: n.needType as NeedType,
            earnCategory: n.earnCategory as EarnCategory | null,
            connectCategory: n.connectCategory as ConnectCategory | null,
            budgetMin: n.budgetMin,
            budgetMax: n.budgetMax,
            deadline: n.deadline ? new Date(n.deadline) : null,
            locationText: n.locationText ?? defaultLoc,
            lat: n.lat ?? defaultLat,
            lng: n.lng ?? defaultLng,
            isPaid: n.budgetMin != null || n.budgetMax != null,
            parentNeedId: parent.id,
          },
        }),
      ))

      // Activate referral on first-ever need post
      if (isFirstNeed) {
        const referral = await tx.referral.findUnique({
          where: { refereeId: userId },
        })
        if (referral && referral.status === 'PENDING') {
          const REFERRAL_PTS = 15
          await tx.referral.update({
            where: { refereeId: userId },
            data: { status: 'ACTIVATED', activatedAt: new Date() },
          })
          // Points to referee
          await tx.pointsLedger.create({
            data: { userId, delta: REFERRAL_PTS, reason: 'REFERRAL_BONUS', refId: referral.id },
          })
          await tx.profile.update({
            where: { userId },
            data: { pointsTotal: { increment: REFERRAL_PTS } },
          })
          // Points to referrer
          await tx.pointsLedger.create({
            data: { userId: referral.referrerId, delta: REFERRAL_PTS, reason: 'REFERRAL_ACTIVATED', refId: referral.id },
          })
          await tx.profile.update({
            where: { userId: referral.referrerId },
            data: { pointsTotal: { increment: REFERRAL_PTS } },
          })
          await pushNotification(tx, {
            userId: referral.referrerId,
            type: 'POINTS_AWARDED',
            title: 'Referral activated! 🎉',
            body: 'Someone you referred just posted their first need. +15 points!',
            refType: 'USER',
            refId: userId,
          })
        }
      }

      return { parent, subs }
    })

    // Broadcast new need to all connected users so feeds update instantly
    try { getIo()?.emit('new_need', created.parent) } catch {}

    // Check & notify users whose selected skills match the new need
    notifyMatchingSkillUsers(created.parent).catch((err) =>
      console.error('[skill-matching] Error notifying for parent need:', err),
    )
    for (const sub of created.subs) {
      notifyMatchingSkillUsers(sub).catch((err) =>
        console.error('[skill-matching] Error notifying for sub need:', err),
      )
    }

    res.status(201).json({
      parent: created.parent,
      subs: created.subs,
      softFlagged: verdict.softFlag,
    })
  } catch (err) { next(err) }
})

// ─── GET /needs — public feed with proximity + interest ranking ─────────────

needsRouter.get('/', async (req, res, next) => {
  const parsed = feedQuery.safeParse(req.query)
  if (!parsed.success) return next(badRequest('Invalid feed query', 'INVALID_QUERY'))
  const q = parsed.data
  const authedUserId = tryGetUserId(req)
  const sortMode = (req.query.sort as string | undefined) ?? 'smart'

  try {
    // Load the authenticated user's profile to drive personalized ranking.
    // Falls back to query params when not signed in or missing fields.
    let userLat: number | null = q.lat ?? null
    let userLng: number | null = q.lng ?? null
    let userInterests: string[] = q.interests?.map((i) => i.toLowerCase()) ?? []
    let userSignal: string | null = null // full profile string for embedding

    if (authedUserId) {
      const me = await prisma.profile.findUnique({
        where: { userId: authedUserId },
        select: {
          lat: true, lng: true, bio: true,
          promptSkill: true, promptCollab: true, promptNeed: true,
          interests: { include: { interest: { select: { label: true } } } },
          skills: { include: { skill: { select: { label: true } } } },
        },
      })
      if (me) {
        if (userLat == null) userLat = me.lat
        if (userLng == null) userLng = me.lng
        const profileInterestLabels = me.interests
          .map((pi) => pi.interest.label.toLowerCase())
        if (userInterests.length === 0) userInterests = profileInterestLabels
        userSignal = userSignalText(me)
      }
    }

    // Pre-filter at the DB layer with the cheap SQL-side filters. Distance,
    // gender, interests, and block filters run in application code below —
    // Neon's HTTP driver keeps this fast enough for the demo scale.
    const needsRaw = await prisma.need.findMany({
      where: {
        status: q.status ?? 'OPEN',
        parentNeedId: null,
        ...(q.type ? { needType: q.type } : {}),
        ...(q.minBudget != null ? { budgetMax: { gte: q.minBudget } } : {}),
        ...(q.maxBudget != null ? { budgetMin: { lte: q.maxBudget } } : {}),
      },
      include: {
        poster: {
          select: {
            id: true, displayName: true, emailVerifiedAt: true, phoneVerifiedAt: true,
            profile: { select: {
              avatarUrl: true, gender: true, lat: true, lng: true, faceVerifiedAt: true,
              bio: true,
              personalityTraits: true, personalityNickname: true, personalityVibeTags: true,
              interests: { include: { interest: { select: { label: true } } } },
            } },
          },
        },
        subNeeds: { select: { id: true, title: true, budgetMin: true, budgetMax: true } },
        _count: { select: { responses: true } },
      },
      orderBy: { createdAt: 'desc' },
      take: q.take ?? 60,
      skip: q.skip,
    })

    // Batch-fetch trust-score "track record" inputs for every poster on this
    // page in 3 grouped queries instead of one per need (keeps the feed fast).
    const posterIds = [...new Set(needsRaw.map((n) => n.posterId))]
    const [certGroups, fulfilledGroups, reviewGroups] = await Promise.all([
      prisma.certificate.groupBy({ by: ['userId'], where: { userId: { in: posterIds }, status: 'APPROVED' }, _count: { id: true } }),
      prisma.need.groupBy({ by: ['posterId'], where: { posterId: { in: posterIds }, status: 'FULFILLED' }, _count: { id: true } }),
      prisma.review.groupBy({ by: ['revieweeId'], where: { revieweeId: { in: posterIds } }, _avg: { rating: true }, _count: { id: true } }),
    ])
    const certByUser = new Map(certGroups.map((g) => [g.userId, g._count.id]))
    const fulfilledByUser = new Map(fulfilledGroups.map((g) => [g.posterId, g._count.id]))
    const reviewByUser = new Map(reviewGroups.map((g) => [g.revieweeId, { avg: g._avg.rating ?? 0, count: g._count.id }]))
    const trustScoreByPoster = new Map(
      posterIds.map((id) => {
        const need = needsRaw.find((n) => n.posterId === id)!
        const review = reviewByUser.get(id)
        return [id, computeTrustScore({
          emailVerifiedAt: need.poster.emailVerifiedAt,
          phoneVerifiedAt: need.poster.phoneVerifiedAt,
          faceVerifiedAt: need.poster.profile?.faceVerifiedAt ?? null,
          approvedCertificateCount: certByUser.get(id) ?? 0,
          fulfilledNeedCount: fulfilledByUser.get(id) ?? 0,
          avgRating: review?.avg ?? 0,
          ratingCount: review?.count ?? 0,
        })]
      }),
    )

    // Filter first, then batch-embed the survivors.
    type Filtered = { need: (typeof needsRaw)[number]; distanceKm: number | null }
    const filtered: Filtered[] = []
    for (const n of needsRaw) {
      // Gender filter (poster's declared gender).
      if (q.genders?.length && (!n.poster.profile?.gender ||
          !q.genders.map((g) => g.toLowerCase()).includes(n.poster.profile.gender.toLowerCase()))) continue

      // Distance filter (hard cap — user's chosen radius).
      let distanceKm: number | null = null
      const needLat = n.lat ?? n.poster.profile?.lat ?? null
      const needLng = n.lng ?? n.poster.profile?.lng ?? null
      if (userLat != null && userLng != null && needLat != null && needLng != null) {
        distanceKm = haversineKm(userLat, userLng, needLat, needLng)
        if (q.distanceKm != null && distanceKm > q.distanceKm) continue
      }

      // Explicit interest filter (still restrictive — user has toggled it).
      if (q.interests?.length) {
        const hay = `${n.title} ${n.description}`.toLowerCase()
        const hit = q.interests.some((i) => hay.includes(i.toLowerCase()))
        if (!hit) continue
      }

      // Block filter.
      if (authedUserId && await isBlockedBetween(authedUserId, n.posterId)) continue

      filtered.push({ need: n, distanceKm })
    }

    // Semantic ranking: batch-embed all filtered needs + the user profile in
    // parallel, then compute cosine similarity. Falls back to substring
    // heuristic if Cohere is unavailable.
    let usedEmbeddings = false
    const needSimilarityById = new Map<string, number>()
    if (embeddingsAvailable() && filtered.length > 0 && userSignal) {
      const [userVec, needVecs] = await Promise.all([
        embedBatch([userSignal], 'search_query'),
        embedBatch(filtered.map((f) => needSignalText(f.need)), 'search_document'),
      ])
      if (userVec && needVecs && userVec[0]) {
        usedEmbeddings = true
        filtered.forEach((f, i) => {
          needSimilarityById.set(f.need.id, cosineSimilarity(userVec[0], needVecs[i]))
        })
      }
    }

    type Ranked = Filtered & { score: number; semantic: number | null }
    const ranked: Ranked[] = filtered.map((f) => {
      const semantic = needSimilarityById.get(f.need.id) ?? null
      const trustScore = trustScoreByPoster.get(f.need.posterId) ?? 0
      return {
        ...f,
        semantic,
        score: scoreNeed(f.need, f.distanceKm, userInterests, semantic, trustScore),
      }
    })

    // Sort. "smart" = personalized ranking, "newest" = createdAt DESC, "distance" = nearest first.
    if (sortMode === 'newest') {
      ranked.sort((a, b) => b.need.createdAt.getTime() - a.need.createdAt.getTime())
    } else if (sortMode === 'distance') {
      ranked.sort((a, b) => (a.distanceKm ?? Infinity) - (b.distanceKm ?? Infinity))
    } else {
      // Default: smart — highest score first, tie-breaker by recency.
      ranked.sort((a, b) => {
        if (b.score !== a.score) return b.score - a.score
        return b.need.createdAt.getTime() - a.need.createdAt.getTime()
      })
    }

    const list = ranked.map((r) => {
      const trustScore = trustScoreByPoster.get(r.need.posterId) ?? 0
      const needLat = r.need.lat ?? r.need.poster.profile?.lat ?? null
      const needLng = r.need.lng ?? r.need.poster.profile?.lng ?? null
      return {
        ...r.need,
        lat: needLat,
        lng: needLng,
        poster: {
          ...r.need.poster,
          profile: r.need.poster.profile ? { ...r.need.poster.profile, trustScore } : r.need.poster.profile,
        },
        offerCount: r.need._count.responses,
        _score: Math.round(r.score * 100) / 100,
        _semantic: r.semantic != null ? Math.round(r.semantic * 100) / 100 : null,
        _distanceKm: r.distanceKm != null ? Math.round(r.distanceKm * 10) / 10 : null,
      }
    })
    res.json({
      needs: list,
      count: list.length,
      sort: sortMode,
      ranker: usedEmbeddings ? 'embeddings' : 'heuristic',
    })
  } catch (err) { next(err) }
})

/**
 * Compute a personalized relevance score in [0, 1] for a need.
 *
 * Weights (embeddings mode — when Cohere returned a similarity vector):
 *   EARN:    0.60 semantic + 0.25 proximity + 0.15 freshness
 *   CONNECT: 0.45 semantic + 0.20 proximity + 0.15 freshness + 0.20 trust score
 *
 * Weights (heuristic mode — Cohere unavailable):
 *   EARN:    0.55 interest match + 0.30 proximity + 0.15 freshness
 *   CONNECT: 0.40 interest match + 0.25 proximity + 0.15 freshness + 0.20 trust score
 *
 * Trust score (see lib/trust-score.ts) only factors into CONNECT ranking —
 * meeting a stranger in person is the actual safety-sensitive surface; Earn
 * stays purely skill/proximity/freshness driven. It's a meaningful slice
 * (20%) but capped so relevance + proximity still dominate — a new, unverified
 * user must stay discoverable, not buried (Needhub.txt §8/§11).
 *
 * The semantic path catches near-synonym matches ("need someone to fix my
 * code" vs. user with interest "coding" both rank high). The heuristic path
 * only catches literal substring hits.
 */
function scoreNeed(
  need: { title: string; description: string; createdAt: Date; earnCategory: string | null; connectCategory: string | null; needType: string },
  distanceKm: number | null,
  userInterestLabels: string[],
  semanticSimilarity: number | null,
  trustScore: number, // 0-100, ignored for EARN needs
): number {
  // Proximity — 1 at 0km, 0 at 30km+, linear decay.
  const proximityScore = distanceKm == null
    ? 0.5
    : Math.max(0, 1 - distanceKm / 30)

  // Freshness — 1 at posting time, 0 after 7 days.
  const hoursOld = (Date.now() - need.createdAt.getTime()) / 3_600_000
  const freshnessScore = Math.max(0, 1 - hoursOld / (24 * 7))

  const isConnect = need.needType === 'CONNECT'
  const trustScore01 = trustScore / 100

  if (semanticSimilarity != null) {
    // Cosine similarity is in [-1, 1]; normalize to [0, 1] for combining.
    const semanticScore = Math.max(0, (semanticSimilarity + 1) / 2)
    return isConnect
      ? 0.45 * semanticScore + 0.20 * proximityScore + 0.15 * freshnessScore + 0.20 * trustScore01
      : 0.60 * semanticScore + 0.25 * proximityScore + 0.15 * freshnessScore
  }

  // Heuristic fallback — substring hits on title/description/category.
  let interestScore = 0.5
  if (userInterestLabels.length > 0) {
    const hay = `${need.title} ${need.description} ${need.earnCategory ?? ''} ${need.connectCategory ?? ''}`.toLowerCase()
    const hits = userInterestLabels.filter((i) => i.length > 1 && hay.includes(i)).length
    interestScore = Math.min(1, hits / Math.min(3, userInterestLabels.length))
  }
  return isConnect
    ? 0.40 * interestScore + 0.25 * proximityScore + 0.15 * freshnessScore + 0.20 * trustScore01
    : 0.55 * interestScore + 0.30 * proximityScore + 0.15 * freshnessScore
}

// ─── GET /needs/:id — public detail ──────────────────────────────────────────

needsRouter.get('/:id', async (req, res, next) => {
  try {
    const need = await prisma.need.findUnique({
      where: { id: req.params.id },
      include: {
        poster: {
          select: {
            id: true, displayName: true, emailVerifiedAt: true, phoneVerifiedAt: true,
            profile: { select: { avatarUrl: true, bio: true, pointsTotal: true, faceVerifiedAt: true } },
          },
        },
        subNeeds: true,
        _count: { select: { responses: true } },
      },
    })
    if (!need) return next(notFound('Need not found', 'NEED_NOT_FOUND'))

    const [approvedCertificateCount, fulfilledNeedCount, reviewAgg] = await Promise.all([
      prisma.certificate.count({ where: { userId: need.posterId, status: 'APPROVED' } }),
      prisma.need.count({ where: { posterId: need.posterId, status: 'FULFILLED' } }),
      prisma.review.aggregate({ where: { revieweeId: need.posterId }, _avg: { rating: true }, _count: { id: true } }),
    ])
    const trustScore = computeTrustScore({
      emailVerifiedAt: need.poster.emailVerifiedAt,
      phoneVerifiedAt: need.poster.phoneVerifiedAt,
      faceVerifiedAt: need.poster.profile?.faceVerifiedAt ?? null,
      approvedCertificateCount,
      fulfilledNeedCount,
      avgRating: reviewAgg._avg.rating ?? 0,
      ratingCount: reviewAgg._count.id,
    })

    res.json({
      ...need,
      poster: { ...need.poster, profile: need.poster.profile ? { ...need.poster.profile, trustScore } : need.poster.profile },
      offerCount: need._count.responses,
    })
  } catch (err) { next(err) }
})

// ─── GET /needs/mine — my posted needs ───────────────────────────────────────

needsRouter.get('/mine/list', authenticate, async (req, res, next) => {
  const userId = (req as AuthedRequest).userId
  try {
    const rows = await prisma.need.findMany({
      where: { posterId: userId },
      orderBy: { createdAt: 'desc' },
      include: { subNeeds: { select: { id: true, title: true, status: true } } },
    })
    res.json({ needs: rows })
  } catch (err) { next(err) }
})

// ─── PATCH /needs/:id/status — poster only ───────────────────────────────────

needsRouter.patch('/:id/status', authenticate, async (req, res, next) => {
  const parsed = statusBody.safeParse(req.body)
  if (!parsed.success) return next(badRequest('Invalid status payload', 'INVALID_BODY'))
  const userId = (req as AuthedRequest).userId
  try {
    const need = await prisma.need.findUnique({ where: { id: req.params.id } })
    if (!need) return next(notFound('Need not found', 'NEED_NOT_FOUND'))
    if (need.posterId !== userId) return next(forbidden('Only the poster can change status', 'NOT_POSTER'))
    const updated = await prisma.need.update({
      where: { id: need.id }, data: { status: parsed.data.status },
    })
    res.json(updated)
  } catch (err) { next(err) }
})

// ─── PATCH /needs/:id — edit need (poster only) ──────────────────────────────

const editNeedSchema = z.object({
  title: z.string().min(3).max(120).optional(),
  description: z.string().min(5).max(3000).optional(),
  category: z.string().optional(),
  budgetMin: z.number().int().min(0).nullable().optional(),
  budgetMax: z.number().int().min(0).nullable().optional(),
  locationText: z.string().optional(),
})

needsRouter.patch('/:id', authenticate, async (req, res, next) => {
  const parsed = editNeedSchema.safeParse(req.body)
  if (!parsed.success) return next(badRequest('Invalid edit payload', 'INVALID_BODY'))
  const userId = (req as AuthedRequest).userId
  try {
    const need = await prisma.need.findUnique({ where: { id: req.params.id } })
    if (!need) return next(notFound('Need not found', 'NEED_NOT_FOUND'))
    if (need.posterId !== userId) return next(forbidden('Only the poster can edit this need', 'NOT_POSTER'))
    if (need.status === 'FULFILLED') return next(forbidden('Cannot edit a frozen/fulfilled need', 'NEED_FROZEN'))

    const updated = await prisma.need.update({
      where: { id: need.id },
      data: {
        ...(parsed.data.title !== undefined && { title: parsed.data.title }),
        ...(parsed.data.description !== undefined && { description: parsed.data.description }),
        ...(parsed.data.category !== undefined && { category: parsed.data.category }),
        ...(parsed.data.budgetMin !== undefined && { budgetMin: parsed.data.budgetMin }),
        ...(parsed.data.budgetMax !== undefined && { budgetMax: parsed.data.budgetMax }),
        ...(parsed.data.locationText !== undefined && { locationText: parsed.data.locationText }),
      },
    })
    res.json(updated)
  } catch (err) { next(err) }
})

// ─── DELETE /needs/:id — delete need (poster only) ────────────────────────────

needsRouter.delete('/:id', authenticate, async (req, res, next) => {
  const userId = (req as AuthedRequest).userId
  try {
    const need = await prisma.need.findUnique({ where: { id: req.params.id } })
    if (!need) return next(notFound('Need not found', 'NEED_NOT_FOUND'))
    if (need.posterId !== userId) return next(forbidden('Only the poster can delete this need', 'NOT_POSTER'))

    await prisma.$transaction([
      prisma.interestResponse.deleteMany({ where: { needId: need.id } }),
      prisma.need.delete({ where: { id: need.id } }),
    ])
    res.json({ success: true, message: 'Need deleted' })
  } catch (err) { next(err) }
})

// ─── POST /needs/:id/responses — offer / interest ────────────────────────────

needsRouter.post('/:id/responses', authenticate, upload.single('workSample'), async (req, res, next) => {
  const parsed = respondBody.safeParse(req.body)
  if (!parsed.success) return next(badRequest('Invalid response payload', 'INVALID_BODY'))
  const userId = (req as AuthedRequest).userId

  try {
    const need = await prisma.need.findUnique({ where: { id: req.params.id } })
    if (!need) return next(notFound('Need not found', 'NEED_NOT_FOUND'))
    if (need.status !== 'OPEN') return next(badRequest('This need is frozen and no longer accepting offers', 'NEED_FROZEN'))
    if (need.posterId === userId) return next(badRequest("Can't respond to your own need", 'SELF_RESPONSE'))
    if (await isBlockedBetween(userId, need.posterId)) return next(forbidden('Cannot respond', 'BLOCKED'))

    const verdict = await checkText(parsed.data.message)
    if (verdict.hardBlocked) {
      getSystemUserId().then((reporterId) => autoReport({
        reporterId,
        targetType: 'NEED',
        targetId: need.id,
        reason: `Blocked response: ${verdict.reasons.join(', ')}`,
        source: 'moderation_hard',
        detail: { matches: verdict.matches, responderId: userId },
      })).catch((e) => console.error('[moderation] autoReport failed:', e.message))
      return next(unprocessable('Content violates community rules', 'MODERATION_HARD_BLOCK'))
    }

    let workSampleUrl: string | null = null
    if (req.file) {
      const key = storageKey(`work-samples/${need.id}`, req.file.originalname)
      workSampleUrl = await uploadFile(key, req.file.buffer, req.file.mimetype)
    }

    const existing = await prisma.interestResponse.findFirst({
      where: { needId: need.id, responderId: userId },
      orderBy: { createdAt: 'desc' },
    })
    if (existing && existing.status !== 'PENDING') {
      return next(badRequest('This response can no longer be edited', 'RESPONSE_FINALIZED'))
    }
    if (existing && !isResponseEditable(existing.createdAt)) {
      return next(badRequest('Responses can only be edited within 10 minutes', 'RESPONSE_EDIT_WINDOW_EXPIRED'))
    }

    if (existing) {
      await createResponseRevisionBestEffort({
        responseId: existing.id,
        message: existing.message,
        quotedPrice: existing.quotedPrice,
        workSampleUrl: existing.workSampleUrl,
      })
      const response = await prisma.interestResponse.update({
        where: { id: existing.id },
        data: {
          message: parsed.data.message,
          quotedPrice: parsed.data.quotedPrice ?? null,
          workSampleUrl: workSampleUrl ?? (parsed.data.removeWorkSample ? null : existing.workSampleUrl),
        },
      })
      return res.json({ response, softFlagged: verdict.softFlag })
    }

    const response = await prisma.$transaction(async (tx) => {
      const created = await tx.interestResponse.create({
        data: {
          needId: need.id,
          responderId: userId,
          message: parsed.data.message,
          quotedPrice: parsed.data.quotedPrice ?? null,
          workSampleUrl,
        },
      })
      await pushNotification(tx, {
        userId: need.posterId,
        type: 'NEED_RESPONSE_RECEIVED',
        title: 'New response on your need',
        body: parsed.data.message.slice(0, 140),
        refType: 'need',
        refId: need.id,
      })
      emitToUser(need.posterId, 'new_response', { needId: need.id })
      return created
    })

    res.status(201).json({ response, softFlagged: verdict.softFlag })
  } catch (err) { next(err) }
})

// ─── GET /needs/:id/responses — poster-only ──────────────────────────────────

needsRouter.get('/:id/responses', authenticate, async (req, res, next) => {
  try {
    const need = await prisma.need.findUnique({ where: { id: req.params.id } })
    if (!need) return next(notFound('Need not found', 'NEED_NOT_FOUND'))
    let responses
    try {
      responses = await prisma.interestResponse.findMany({
        where: { needId: need.id },
        include: {
          responder: {
            select: {
              id: true, displayName: true,
              profile: { select: { avatarUrl: true, pointsTotal: true } },
            },
          },
          revisions: { orderBy: { createdAt: 'desc' } },
        },
        orderBy: { createdAt: 'desc' },
      })
    } catch (err) {
      if (!isMissingResponseRevisionTable(err)) throw err
      responses = await prisma.interestResponse.findMany({
        where: { needId: need.id },
        include: {
          responder: {
            select: {
              id: true, displayName: true,
              profile: { select: { avatarUrl: true, pointsTotal: true } },
            },
          },
        },
        orderBy: { createdAt: 'desc' },
      })
    }
    res.json({ responses })
  } catch (err) { next(err) }
})

// ─── PATCH /needs/:id/responses/:respId/edit — responder edits own offer ─────

needsRouter.patch('/:id/responses/:respId/edit', authenticate, upload.single('workSample'), async (req, res, next) => {
  const parsed = editResponseBody.safeParse(req.body)
  if (!parsed.success) return next(badRequest('Invalid response payload', 'INVALID_BODY'))
  const userId = (req as AuthedRequest).userId

  try {
    const response = await prisma.interestResponse.findUnique({ where: { id: req.params.respId } })
    if (!response || response.needId !== req.params.id) return next(notFound('Response not found', 'RESPONSE_NOT_FOUND'))
    if (response.responderId !== userId) return next(forbidden('Only the responder can edit this offer', 'NOT_RESPONDER'))
    if (response.status !== 'PENDING') return next(badRequest('This offer can no longer be edited', 'RESPONSE_FINALIZED'))
    if (!isResponseEditable(response.createdAt)) {
      return next(badRequest('Responses can only be edited within 10 minutes', 'RESPONSE_EDIT_WINDOW_EXPIRED'))
    }

    const verdict = await checkText(parsed.data.message)
    if (verdict.hardBlocked) return next(unprocessable('Content violates community rules', 'MODERATION_HARD_BLOCK'))

    let workSampleUrl = response.workSampleUrl
    if (req.file) {
      const key = storageKey(`work-samples/${response.needId}`, req.file.originalname)
      workSampleUrl = await uploadFile(key, req.file.buffer, req.file.mimetype)
    } else if (parsed.data.removeWorkSample) {
      workSampleUrl = null
    }

    await createResponseRevisionBestEffort({
      responseId: response.id,
      message: response.message,
      quotedPrice: response.quotedPrice,
      workSampleUrl: response.workSampleUrl,
    })
    const updated = await prisma.interestResponse.update({
      where: { id: response.id },
      data: { message: parsed.data.message, quotedPrice: parsed.data.quotedPrice ?? null, workSampleUrl },
    })
    res.json({ response: updated, softFlagged: verdict.softFlag })
  } catch (err) { next(err) }
})

// ─── DELETE /needs/:id/responses/:respId — delete / withdraw offer (responder only) ──

needsRouter.delete('/:id/responses/:respId', authenticate, async (req, res, next) => {
  const userId = (req as AuthedRequest).userId
  try {
    const response = await prisma.interestResponse.findUnique({ where: { id: req.params.respId } })
    if (!response || response.needId !== req.params.id) return next(notFound('Response not found', 'RESPONSE_NOT_FOUND'))
    if (response.responderId !== userId) return next(forbidden('Only the responder can delete this offer', 'NOT_RESPONDER'))
    if (response.status === 'ACCEPTED') return next(forbidden('Accepted offers cannot be withdrawn', 'OFFER_ACCEPTED'))

    await prisma.interestResponse.delete({ where: { id: response.id } })
    res.json({ success: true, message: 'Offer withdrawn' })
  } catch (err) { next(err) }
})

// ─── PATCH /needs/:id/responses/:respId — accept / decline ──────────────────

needsRouter.patch('/:id/responses/:respId', authenticate, async (req, res, next) => {
  const parsed = respondDecisionBody.safeParse(req.body)
  if (!parsed.success) return next(badRequest('Invalid decision payload', 'INVALID_BODY'))
  const userId = (req as AuthedRequest).userId

  try {
    const resp = await prisma.interestResponse.findUnique({
      where: { id: req.params.respId },
      include: { need: true },
    })
    if (!resp || resp.needId !== req.params.id) return next(notFound('Response not found', 'RESPONSE_NOT_FOUND'))
    if (resp.need.posterId !== userId) return next(forbidden('Only the poster can decide', 'NOT_POSTER'))

    // Canonical DmThread key: smaller id first (matches messaging router).
    const [userAId, userBId] = userId < resp.responderId
      ? [userId, resp.responderId]
      : [resp.responderId, userId]

    const updated = await prisma.$transaction(async (tx) => {
      const r = await tx.interestResponse.update({
        where: { id: resp.id }, data: { status: parsed.data.status },
      })
      let dmThreadId: string | null = null
      // On accept, spin up both the MessageThread (offer-linked) AND a DmThread
      // (surfaces in /chats). Guarantees the two users can DM after acceptance,
      // even without a friendship, because /chats/dm/:userId/messages checks
      // for accepted InterestResponse to bypass the friends-only rule.
      if (parsed.data.status === 'ACCEPTED') {
        await tx.need.update({
          where: { id: resp.needId },
          data: { status: 'FULFILLED' },
        })
        await tx.messageThread.upsert({
          where: { responseId: r.id },
          create: { responseId: r.id },
          update: {},
        })
        const dm = await tx.dmThread.upsert({
          where: { userAId_userBId: { userAId, userBId } },
          create: { userAId, userBId },
          update: {},
        })
        dmThreadId = dm.id
      }
      await pushNotification(tx, {
        userId: resp.responderId,
        type: 'NEED_RESPONSE_RECEIVED',
        title: parsed.data.status === 'ACCEPTED' ? 'Your response was accepted' : 'Your response was declined',
        body: resp.need.title,
        refType: 'need',
        refId: resp.needId,
      })
      emitToUser(resp.responderId, 'response_decision', { needId: resp.needId, status: parsed.data.status })
      return { r, dmThreadId }
    })

    res.json({ ...updated.r, dmThreadId: updated.dmThreadId })
  } catch (err) { next(err) }
})

// ─── POST /needs/:id/suggest-response — Lyzr AI intro suggestion ─────────────

needsRouter.post('/:id/suggest-response', authenticate, async (req, res, next) => {
  const userId = (req as AuthedRequest).userId
  try {
    const need = await prisma.need.findUnique({ where: { id: req.params.id } })
    if (!need) return next(notFound('Need not found', 'NEED_NOT_FOUND'))

    // Fetch caller's profile to personalize the suggestion
    const profile = await prisma.profile.findUnique({
      where: { userId },
      select: {
        bio: true,
        skills: { include: { skill: { select: { label: true } } } },
        interests: { include: { interest: { select: { label: true } } } },
      },
    })

    const budget = need.budgetMin != null
      ? need.budgetMax != null
        ? `₹${need.budgetMin}–₹${need.budgetMax}`
        : `₹${need.budgetMin}+`
      : null

    const result = await suggestResponse({
      needTitle: need.title,
      needDescription: need.description,
      category: need.needType as 'EARN' | 'CONNECT',
      budget,
      responderBio: profile?.bio ?? null,
      responderSkills: profile?.skills.map((s) => s.skill.label) ?? [],
      responderInterests: profile?.interests.map((i) => i.interest.label) ?? [],
    })

    res.json({ suggestion: result.suggestion, poweredBy: result.poweredBy })
  } catch (err) { next(err) }
})

// ─── helpers ────────────────────────────────────────────────────────────────

async function autoReport(args: {
  reporterId: string
  targetType: ReportTargetType
  targetId: string
  reason: string
  source: 'moderation_hard' | 'moderation_soft'
  detail?: unknown
}) {
  await prisma.$transaction(async (tx) => {
    const report = await tx.report.create({
      data: {
        reporterId: args.reporterId,
        targetType: args.targetType,
        targetId: args.targetId,
        reason: args.reason,
        status: 'OPEN',
      },
    })
    await tx.reportMeta.create({
      data: {
        reportId: report.id,
        source: args.source,
        detail: (args.detail ?? null) as never,
      },
    })
  })
}

function isMissingResponseRevisionTable(err: unknown): boolean {
  return err instanceof Prisma.PrismaClientKnownRequestError &&
    (err.code === 'P2021' || err.code === 'P2022')
}

function isResponseEditable(createdAt: Date): boolean {
  return Date.now() - createdAt.getTime() <= RESPONSE_EDIT_WINDOW_MS
}

async function createResponseRevisionBestEffort(
  data: {
    responseId: string
    message: string
    quotedPrice: number | null
    workSampleUrl: string | null
  },
) {
  try {
    await prisma.responseRevision.create({ data })
  } catch (err) {
    if (isMissingResponseRevisionTable(err)) {
      console.warn('[responses] ResponseRevision table missing; skipping response history until migration is applied')
      return
    }
    console.warn('[responses] Skipping response history after failed revision save:', err instanceof Error ? err.message : err)
  }
}

// ── POST /needs/:id/boost — spend Impact Points to boost a need's visibility ──
// Body: { "tier": "6h" | "24h" | "72h" }
// Costs: 6h = 50 pts | 24h = 100 pts | 72h = 200 pts

const BOOST_TIERS: Record<string, { hours: number; cost: number }> = {
  '6h':  { hours: 6,  cost: 50  },
  '24h': { hours: 24, cost: 100 },
  '72h': { hours: 72, cost: 200 },
}

needsRouter.post('/:id/boost', authenticate, async (req, res, next) => {
  const userId = (req as AuthedRequest).userId
  const needId = req.params.id
  const tier = (req.body.tier as string | undefined)?.toLowerCase()

  if (!tier || !BOOST_TIERS[tier]) {
    return next(badRequest('tier must be "6h", "24h", or "72h"', 'INVALID_TIER'))
  }
  const { hours, cost } = BOOST_TIERS[tier]

  try {
    // 1. Verify the need exists and belongs to the caller
    const need = await prisma.need.findUnique({ where: { id: needId } })
    if (!need) return next(notFound('Need not found'))
    if (need.posterId !== userId) return next(forbidden('You can only boost your own needs'))
    if (need.status !== 'OPEN') return next(badRequest('Only open needs can be boosted', 'NEED_NOT_OPEN'))

    // 2. Check if need is already boosted
    const existingBoost = await prisma.visibilityBoost.findFirst({
      where: { targetId: needId, targetType: 'NEED', expiresAt: { gt: new Date() } },
    })
    if (existingBoost) {
      return next(badRequest(
        `This need is already boosted until ${existingBoost.expiresAt.toISOString()}`,
        'ALREADY_BOOSTED',
      ))
    }

    // 3. Check user's points balance
    const profile = await prisma.profile.findUnique({ where: { userId } })
    if (!profile) return next(notFound('Profile not found'))
    if (profile.pointsTotal < cost) {
      return next(badRequest(
        `Not enough Impact Points. You have ${profile.pointsTotal} pts but need ${cost} pts.`,
        'INSUFFICIENT_POINTS',
      ))
    }

    // 4. Deduct points + create boost in a transaction
    const expiresAt = new Date(Date.now() + hours * 60 * 60 * 1000)
    const [boost] = await prisma.$transaction([
      prisma.visibilityBoost.create({
        data: { userId, targetType: 'NEED', targetId: needId, expiresAt },
      }),
      prisma.profile.update({
        where: { userId },
        data: { pointsTotal: { decrement: cost } },
      }),
      prisma.pointsLedger.create({
        data: {
          userId,
          delta: -cost,
          reason: `Boost need "${need.title}" for ${hours}h`,
          refId: needId,
        },
      }),
    ])

    res.json({
      ok: true,
      boost: { id: boost.id, expiresAt: boost.expiresAt, tier, cost },
      newBalance: profile.pointsTotal - cost,
    })
  } catch (err) { next(err) }
})

// ── GET /needs/:id/boost — check active boost status ──────────────────────────

needsRouter.get('/:id/boost', authenticate, async (req, res, next) => {
  const userId = (req as AuthedRequest).userId
  const needId = req.params.id

  try {
    const need = await prisma.need.findUnique({ where: { id: needId } })
    if (!need) return next(notFound('Need not found'))
    if (need.posterId !== userId) return next(forbidden('Forbidden'))

    const boost = await prisma.visibilityBoost.findFirst({
      where: { targetId: needId, targetType: 'NEED', expiresAt: { gt: new Date() } },
    })

    res.json({
      boosted: !!boost,
      expiresAt: boost?.expiresAt ?? null,
    })
  } catch (err) { next(err) }
})

function tryGetUserId(req: unknown): string | null {
  try {
    const auth = (req as { headers?: Record<string, string> }).headers?.authorization
    if (!auth?.startsWith('Bearer ')) return null
    // Cheap decode without verify — just to filter blocks in the public feed
    // for authenticated callers. If the token is bogus, we treat as anon.
    const [, payload] = auth.slice(7).split('.')
    if (!payload) return null
    const decoded = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'))
    return typeof decoded.sub === 'string' ? decoded.sub : null
  } catch { return null }
}

function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371
  const toRad = (d: number) => (d * Math.PI) / 180
  const dLat = toRad(lat2 - lat1)
  const dLng = toRad(lng2 - lng1)
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
}
