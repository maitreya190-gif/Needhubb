import { Router, type IRouter } from 'express'
import multer from 'multer'
import type { NeedType, EarnCategory, ConnectCategory, ReportTargetType } from '@prisma/client'
import { prisma } from '../../lib/prisma'
import { checkText } from '../../lib/moderation'
import { decomposeNeed } from '../../lib/llm'
import {
  embedBatch, cosineSimilarity, needSignalText, userSignalText, embeddingsAvailable,
} from '../../lib/embeddings'
import { pushNotification } from '../../lib/notifications'
import { getSystemUserId } from '../../lib/system-user'
import { authenticate, type AuthedRequest } from '../../middleware/authenticate'
import { isBlockedBetween } from '../friends/friends.service'
import {
  badRequest, forbidden, notFound, unprocessable,
} from '../../lib/http-error'
import {
  decomposeBody, createNeedBody, feedQuery, respondBody, respondDecisionBody, statusBody,
} from './needs.schemas'
import { uploadFile, storageKey } from '../../lib/storage'

export const needsRouter: IRouter = Router()

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

    const created = await prisma.$transaction(async (tx) => {
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
          locationText: first.locationText ?? null,
          lat: first.lat ?? null,
          lng: first.lng ?? null,
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
            locationText: n.locationText ?? null,
            lat: n.lat ?? null,
            lng: n.lng ?? null,
            isPaid: n.budgetMin != null || n.budgetMax != null,
            parentNeedId: parent.id,
          },
        }),
      ))
      return { parent, subs }
    })

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
        status: 'OPEN',
        parentNeedId: null,
        ...(q.type ? { needType: q.type } : {}),
        ...(q.minBudget != null ? { budgetMax: { gte: q.minBudget } } : {}),
        ...(q.maxBudget != null ? { budgetMin: { lte: q.maxBudget } } : {}),
      },
      include: {
        poster: {
          select: {
            id: true, displayName: true,
            profile: { select: {
              avatarUrl: true, gender: true, lat: true, lng: true,
              interests: { include: { interest: { select: { label: true } } } },
            } },
          },
        },
        subNeeds: { select: { id: true, title: true, budgetMin: true, budgetMax: true } },
      },
      orderBy: { createdAt: 'desc' },
      take: q.take ?? 60,
      skip: q.skip,
    })

    // Filter first, then batch-embed the survivors.
    type Filtered = { need: (typeof needsRaw)[number]; distanceKm: number | null }
    const filtered: Filtered[] = []
    for (const n of needsRaw) {
      // Gender filter (poster's declared gender).
      if (q.genders?.length && (!n.poster.profile?.gender ||
          !q.genders.map((g) => g.toLowerCase()).includes(n.poster.profile.gender.toLowerCase()))) continue

      // Distance filter (hard cap — user's chosen radius).
      let distanceKm: number | null = null
      if (userLat != null && userLng != null && n.lat != null && n.lng != null) {
        distanceKm = haversineKm(userLat, userLng, n.lat, n.lng)
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
      return {
        ...f,
        semantic,
        score: scoreNeed(f.need, f.distanceKm, userInterests, semantic),
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

    const list = ranked.map((r) => ({
      ...r.need,
      _score: Math.round(r.score * 100) / 100,
      _semantic: r.semantic != null ? Math.round(r.semantic * 100) / 100 : null,
      _distanceKm: r.distanceKm != null ? Math.round(r.distanceKm * 10) / 10 : null,
    }))
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
 *   0.60 × semantic match  — cosine similarity between user + need embeddings
 *   0.25 × proximity       — closer needs score higher (0 at 30km+, 1 at 0km)
 *   0.15 × freshness       — recency decay over 7 days
 *
 * Weights (heuristic mode — Cohere unavailable):
 *   0.55 × interest match  — substring hits on title/description
 *   0.30 × proximity
 *   0.15 × freshness
 *
 * The semantic path catches near-synonym matches ("need someone to fix my
 * code" vs. user with interest "coding" both rank high). The heuristic path
 * only catches literal substring hits.
 */
function scoreNeed(
  need: { title: string; description: string; createdAt: Date; earnCategory: string | null; connectCategory: string | null },
  distanceKm: number | null,
  userInterestLabels: string[],
  semanticSimilarity: number | null,
): number {
  // Proximity — 1 at 0km, 0 at 30km+, linear decay.
  const proximityScore = distanceKm == null
    ? 0.5
    : Math.max(0, 1 - distanceKm / 30)

  // Freshness — 1 at posting time, 0 after 7 days.
  const hoursOld = (Date.now() - need.createdAt.getTime()) / 3_600_000
  const freshnessScore = Math.max(0, 1 - hoursOld / (24 * 7))

  if (semanticSimilarity != null) {
    // Cosine similarity is in [-1, 1]; normalize to [0, 1] for combining.
    const semanticScore = Math.max(0, (semanticSimilarity + 1) / 2)
    return 0.60 * semanticScore + 0.25 * proximityScore + 0.15 * freshnessScore
  }

  // Heuristic fallback — substring hits on title/description/category.
  let interestScore = 0.5
  if (userInterestLabels.length > 0) {
    const hay = `${need.title} ${need.description} ${need.earnCategory ?? ''} ${need.connectCategory ?? ''}`.toLowerCase()
    const hits = userInterestLabels.filter((i) => i.length > 1 && hay.includes(i)).length
    interestScore = Math.min(1, hits / Math.min(3, userInterestLabels.length))
  }
  return 0.55 * interestScore + 0.30 * proximityScore + 0.15 * freshnessScore
}

// ─── GET /needs/:id — public detail ──────────────────────────────────────────

needsRouter.get('/:id', async (req, res, next) => {
  try {
    const need = await prisma.need.findUnique({
      where: { id: req.params.id },
      include: {
        poster: {
          select: {
            id: true, displayName: true,
            profile: { select: { avatarUrl: true, bio: true, pointsTotal: true } },
          },
        },
        subNeeds: true,
      },
    })
    if (!need) return next(notFound('Need not found', 'NEED_NOT_FOUND'))
    res.json(need)
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

// ─── POST /needs/:id/responses — offer / interest ────────────────────────────

needsRouter.post('/:id/responses', authenticate, upload.single('workSample'), async (req, res, next) => {
  const parsed = respondBody.safeParse(req.body)
  if (!parsed.success) return next(badRequest('Invalid response payload', 'INVALID_BODY'))
  const userId = (req as AuthedRequest).userId

  try {
    const need = await prisma.need.findUnique({ where: { id: req.params.id } })
    if (!need) return next(notFound('Need not found', 'NEED_NOT_FOUND'))
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
      return created
    })

    res.status(201).json({ response, softFlagged: verdict.softFlag })
  } catch (err) { next(err) }
})

// ─── GET /needs/:id/responses — poster-only ──────────────────────────────────

needsRouter.get('/:id/responses', authenticate, async (req, res, next) => {
  const userId = (req as AuthedRequest).userId
  try {
    const need = await prisma.need.findUnique({ where: { id: req.params.id } })
    if (!need) return next(notFound('Need not found', 'NEED_NOT_FOUND'))
    if (need.posterId !== userId) return next(forbidden('Only the poster can view responses', 'NOT_POSTER'))
    const responses = await prisma.interestResponse.findMany({
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
    res.json({ responses })
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

    const updated = await prisma.$transaction(async (tx) => {
      const r = await tx.interestResponse.update({
        where: { id: resp.id }, data: { status: parsed.data.status },
      })
      // On accept, also spin up the MessageThread if not already
      if (parsed.data.status === 'ACCEPTED') {
        await tx.messageThread.upsert({
          where: { responseId: r.id },
          create: { responseId: r.id },
          update: {},
        })
      }
      await pushNotification(tx, {
        userId: resp.responderId,
        type: 'NEED_RESPONSE_RECEIVED',
        title: parsed.data.status === 'ACCEPTED' ? 'Your response was accepted' : 'Your response was declined',
        body: resp.need.title,
        refType: 'need',
        refId: resp.needId,
      })
      return r
    })

    res.json(updated)
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
