import { Router, type IRouter } from 'express'
import { z } from 'zod'
import { prisma } from '../../lib/prisma'
import { authenticate, type AuthedRequest } from '../../middleware/authenticate'
import { pushNotification } from '../../lib/notifications'
import { badRequest, forbidden, notFound, conflict, unprocessable } from '../../lib/http-error'

export const reviewsRouter: IRouter = Router()

const submitBody = z.object({
  needId: z.string().min(1),
  revieweeId: z.string().min(1),
  rating: z.number().int().min(1).max(5),
  comment: z.string().max(1000).optional(),
})

function pointsForRating(rating: number): number {
  if (rating >= 5) return 20
  if (rating === 4) return 10
  return 0
}

// POST /reviews — the poster or an accepted responder reviews the counterparty.
reviewsRouter.post('/', authenticate, async (req, res, next) => {
  try {
    const me = (req as unknown as AuthedRequest).userId!
    const parsed = submitBody.safeParse(req.body)
    if (!parsed.success) return next(badRequest('Invalid review payload', 'INVALID_BODY'))
    const { needId, revieweeId, rating, comment } = parsed.data

    if (revieweeId === me) return next(badRequest('Cannot review yourself', 'SELF_REVIEW'))

    const need = await prisma.need.findUnique({
      where: { id: needId },
      include: {
        responses: { where: { status: 'ACCEPTED' }, select: { responderId: true } },
      },
    })
    if (!need) return next(notFound('Need not found'))
    if (need.status !== 'FULFILLED' && need.status !== 'IN_PROGRESS')
      return next(unprocessable('Need is not fulfilled or accepted yet', 'NEED_NOT_FULFILLED'))

    // Reviewer must have been either the poster or an accepted responder.
    const isPoster = need.posterId === me
    const isAcceptedResponder = need.responses.some((r) => r.responderId === me)
    if (!isPoster && !isAcceptedResponder)
      return next(forbidden('Not a participant of this need', 'NOT_PARTICIPANT'))

    // Reviewee must be the counterparty.
    const counterpartyIds = new Set<string>([need.posterId, ...need.responses.map((r) => r.responderId)])
    counterpartyIds.delete(me)
    if (!counterpartyIds.has(revieweeId))
      return next(badRequest('Reviewee was not a participant', 'INVALID_REVIEWEE'))

    // Prevent duplicate reviews from this reviewer on this need.
    const existing = await prisma.review.findFirst({
      where: { needId, reviewerId: me },
      select: { id: true },
    })
    if (existing) return next(conflict('Already reviewed this need', 'ALREADY_REVIEWED'))

    const pts = pointsForRating(rating)

    const review = await prisma.$transaction(async (tx) => {
      const created = await tx.review.create({
        data: {
          needId, reviewerId: me, revieweeId, rating,
          comment: comment ?? null,
        },
      })

      if (pts > 0) {
        await tx.pointsLedger.create({
          data: {
            userId: revieweeId,
            delta: pts,
            reason: `Review reward (${rating}★)`,
            refId: created.id,
          },
        })
        await tx.profile.upsert({
          where: { userId: revieweeId },
          update: { pointsTotal: { increment: pts } },
          create: { userId: revieweeId, pointsTotal: pts },
        })
        await pushNotification(tx, {
          userId: revieweeId,
          type: 'POINTS_AWARDED',
          title: `+${pts} points`,
          body: `You earned ${pts} points from a ${rating}★ review.`,
          refType: 'REVIEW', refId: created.id,
        })
      }

      await pushNotification(tx, {
        userId: revieweeId,
        type: 'REVIEW_RECEIVED',
        title: `New ${rating}★ review`,
        body: comment ?? 'Someone reviewed your work',
        refType: 'REVIEW', refId: created.id,
      })

      return created
    })

    res.status(201).json({ review, pointsAwarded: pts })
  } catch (err) { next(err) }
})

// GET /reviews/pending — needs I completed but haven't reviewed the counterparty on.
reviewsRouter.get('/pending', authenticate, async (req, res, next) => {
  try {
    const me = (req as unknown as AuthedRequest).userId!

    // Fulfilled needs where I was a participant.
    const needs = await prisma.need.findMany({
      where: {
        status: 'FULFILLED',
        OR: [
          { posterId: me },
          { responses: { some: { responderId: me, status: 'ACCEPTED' } } },
        ],
      },
      include: {
        poster: { select: { id: true, displayName: true, profile: { select: { avatarUrl: true } } } },
        responses: {
          where: { status: 'ACCEPTED' },
          include: {
            responder: {
              select: { id: true, displayName: true, profile: { select: { avatarUrl: true } } },
            },
          },
        },
        reviews: { where: { reviewerId: me }, select: { id: true } },
      },
      orderBy: { createdAt: 'desc' },
    })

    const pending = needs
      .filter((n) => n.reviews.length === 0)
      .map((n) => {
        const counterparty = n.posterId === me
          ? n.responses[0]?.responder ?? null
          : n.poster
        return {
          needId: n.id,
          needTitle: n.title,
          counterparty,
        }
      })
      .filter((p) => p.counterparty != null)

    res.json(pending)
  } catch (err) { next(err) }
})

// GET /reviews/by-me — reviews I wrote (people who helped me + people I helped and rated).
reviewsRouter.get('/by-me', authenticate, async (req, res, next) => {
  try {
    const me = (req as unknown as AuthedRequest).userId!
    const rows = await prisma.review.findMany({
      where: { reviewerId: me },
      include: {
        reviewee: { select: { id: true, displayName: true, profile: { select: { avatarUrl: true } } } },
        need: { select: { id: true, title: true } },
      },
      orderBy: { createdAt: 'desc' },
    })
    const count = rows.length
    const avg = count === 0 ? 0 : rows.reduce((s, r) => s + r.rating, 0) / count
    res.json({ reviews: rows, avg: Math.round(avg * 10) / 10, count })
  } catch (err) { next(err) }
})

// GET /reviews/for/:userId — public reviews of a user + avg + count.
reviewsRouter.get('/for/:userId', async (req, res, next) => {
  try {
    const rows = await prisma.review.findMany({
      where: { revieweeId: req.params.userId },
      include: {
        reviewer: { select: { id: true, displayName: true, profile: { select: { avatarUrl: true } } } },
        need: { select: { id: true, title: true } },
      },
      orderBy: { createdAt: 'desc' },
    })
    const count = rows.length
    const avg = count === 0 ? 0 : rows.reduce((s, r) => s + r.rating, 0) / count
    res.json({ reviews: rows, avg: Math.round(avg * 10) / 10, count })
  } catch (err) { next(err) }
})

// GET /reviews/need/:needId — fetch reviews for a specific need with privacy protection.
// Written feedback (comment) is only visible to the 2 participants (poster and helper).
reviewsRouter.get('/need/:needId', async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization
    let me: string | null = null
    if (authHeader?.startsWith('Bearer ')) {
      try {
        const token = authHeader.substring(7)
        const jwt = require('jsonwebtoken')
        const decoded = jwt.verify(token, process.env.JWT_SECRET || 'secret') as { userId?: string }
        me = decoded.userId ?? null
      } catch (_) {}
    }

    const need = await prisma.need.findUnique({
      where: { id: req.params.needId },
      include: { responses: { where: { status: 'ACCEPTED' }, select: { responderId: true } } },
    })
    if (!need) return next(notFound('Need not found'))

    const reviews = await prisma.review.findMany({
      where: { needId: req.params.needId },
      include: {
        reviewer: { select: { id: true, displayName: true, profile: { select: { avatarUrl: true } } } },
        reviewee: { select: { id: true, displayName: true, profile: { select: { avatarUrl: true } } } },
      },
      orderBy: { createdAt: 'desc' },
    })

    const participants = new Set<string>([need.posterId, ...need.responses.map((r) => r.responderId)])
    const isParticipant = me != null && participants.has(me)

    const sanitized = reviews.map((r) => ({
      id: r.id,
      needId: r.needId,
      reviewerId: r.reviewerId,
      reviewer: r.reviewer,
      revieweeId: r.revieweeId,
      reviewee: r.reviewee,
      rating: r.rating,
      comment: isParticipant ? r.comment : null, // Private comment visible only to participants!
      createdAt: r.createdAt,
    }))

    res.json({ reviews: sanitized, isParticipant })
  } catch (err) { next(err) }
})

