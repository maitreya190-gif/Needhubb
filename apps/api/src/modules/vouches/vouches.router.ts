import { Router, type IRouter } from 'express'
import { prisma } from '../../lib/prisma'
import { authenticate, type AuthedRequest } from '../../middleware/authenticate'
import { badRequest, notFound, forbidden, conflict } from '../../lib/http-error'
import {
  evaluateNewVouch, stripInternalVouchFields, suggestSkillsForCompletedNeed,
} from '../../lib/vouching'
import { pushNotification } from '../../lib/notifications'
import { createVouchBody, editVouchBody } from './vouches.schemas'

export const vouchesRouter: IRouter = Router()

// ─── POST /vouches — endorse a specific skill on someone's profile ─────────

vouchesRouter.post('/', authenticate, async (req, res, next) => {
  const parsed = createVouchBody.safeParse(req.body)
  if (!parsed.success) return next(badRequest('Invalid vouch payload', 'INVALID_BODY'))
  const voucherId = (req as AuthedRequest).userId!
  const { voucheeId, skillId, testimonial } = parsed.data

  try {
    if (voucheeId === voucherId) return next(badRequest('Cannot vouch for yourself', 'SELF_VOUCH'))

    const vouchee = await prisma.user.findUnique({
      where: { id: voucheeId },
      select: { profile: { select: { id: true, skills: { where: { skillId }, select: { skillId: true } } } } },
    })
    if (!vouchee) return next(notFound('User not found', 'USER_NOT_FOUND'))
    // Requirement 1: only for skills actually listed on their profile.
    if (!vouchee.profile || vouchee.profile.skills.length === 0) {
      return next(badRequest('That skill is not on this user\'s profile', 'SKILL_NOT_LISTED'))
    }

    const existing = await prisma.vouch.findUnique({
      where: { voucherId_voucheeId_skillId: { voucherId, voucheeId, skillId } },
    })
    if (existing) return next(conflict('You already vouched for this skill — edit it instead', 'ALREADY_VOUCHED'))

    const evaluation = await evaluateNewVouch(voucherId, voucheeId)

    const vouch = await prisma.vouch.create({
      data: {
        voucherId, voucheeId, skillId,
        testimonial: testimonial ?? null,
        verified: evaluation.verified,
        credibilityWeight: evaluation.credibilityWeight,
        suspicious: evaluation.suspicious,
      },
    })

    const [voucher, skill] = await Promise.all([
      prisma.user.findUnique({ where: { id: voucherId }, select: { displayName: true } }),
      prisma.skill.findUnique({ where: { id: skillId }, select: { label: true } }),
    ])
    await pushNotification(prisma, {
      userId: voucheeId,
      type: 'VOUCH_RECEIVED',
      title: 'New skill vouch',
      body: `${voucher?.displayName ?? 'Someone'} vouched for your ${skill?.label ?? 'skill'} skill`,
      refType: 'VOUCH',
      refId: vouch.id,
    })

    // Suspicious vouches are silently down-weighted, never rejected or
    // flagged to the submitter — requirement 8. The response is identical
    // either way.
    res.status(201).json(stripInternalVouchFields(vouch))
  } catch (err) { next(err) }
})

// ─── PATCH /vouches/:id — edit your own testimonial ─────────────────────────

vouchesRouter.patch('/:id', authenticate, async (req, res, next) => {
  const parsed = editVouchBody.safeParse(req.body)
  if (!parsed.success) return next(badRequest('Invalid edit payload', 'INVALID_BODY'))
  const userId = (req as AuthedRequest).userId!

  try {
    const vouch = await prisma.vouch.findUnique({ where: { id: req.params.id } })
    if (!vouch) return next(notFound('Vouch not found', 'VOUCH_NOT_FOUND'))
    if (vouch.voucherId !== userId) return next(forbidden('Only the voucher can edit this vouch', 'NOT_VOUCHER'))

    // Testimonial text has no bearing on verified/collaboration/trust — the
    // credibility weight computed at creation stays valid, no re-evaluation.
    const updated = await prisma.vouch.update({
      where: { id: vouch.id },
      data: { testimonial: parsed.data.testimonial },
    })
    res.json(stripInternalVouchFields(updated))
  } catch (err) { next(err) }
})

// ─── DELETE /vouches/:id — withdraw your own vouch ──────────────────────────

vouchesRouter.delete('/:id', authenticate, async (req, res, next) => {
  const userId = (req as AuthedRequest).userId!
  try {
    const vouch = await prisma.vouch.findUnique({ where: { id: req.params.id } })
    if (!vouch) return next(notFound('Vouch not found', 'VOUCH_NOT_FOUND'))
    if (vouch.voucherId !== userId) return next(forbidden('Only the voucher can withdraw this vouch', 'NOT_VOUCHER'))

    await prisma.vouch.delete({ where: { id: vouch.id } })
    res.json({ success: true, message: 'Vouch withdrawn' })
  } catch (err) { next(err) }
})

// ─── GET /vouches/given — vouches I have given, for managing them ──────────

vouchesRouter.get('/given', authenticate, async (req, res, next) => {
  const userId = (req as AuthedRequest).userId!
  try {
    const vouches = await prisma.vouch.findMany({
      where: { voucherId: userId },
      include: { skill: { select: { label: true } }, vouchee: { select: { id: true, displayName: true } } },
      orderBy: { createdAt: 'desc' },
    })
    res.json({ vouches: vouches.map(stripInternalVouchFields) })
  } catch (err) { next(err) }
})

// ─── GET /vouches/suggest — AI-assisted skill suggestions ──────────────────
//
// Assistance only, per requirement 3 — this never creates a vouch. The
// caller must have actually completed the given Need with the vouchee (one
// posted it, the other's response was accepted, and it reached FULFILLED),
// so the suggestion is always grounded in a real, verifiable interaction.

vouchesRouter.get('/suggest', authenticate, async (req, res, next) => {
  const voucherId = (req as AuthedRequest).userId!
  const needId = typeof req.query.needId === 'string' ? req.query.needId : null
  const voucheeId = typeof req.query.voucheeId === 'string' ? req.query.voucheeId : null
  if (!needId || !voucheeId) return next(badRequest('needId and voucheeId are required', 'INVALID_QUERY'))

  try {
    const need = await prisma.need.findUnique({
      where: { id: needId },
      include: { responses: { where: { status: 'ACCEPTED' }, select: { responderId: true } } },
    })
    if (!need) return next(notFound('Need not found', 'NEED_NOT_FOUND'))
    if (need.status !== 'FULFILLED') {
      return next(badRequest('Need has not been completed yet', 'NEED_NOT_FULFILLED'))
    }

    const acceptedResponderIds = need.responses.map((r) => r.responderId)
    const wereCounterparts =
      (need.posterId === voucherId && acceptedResponderIds.includes(voucheeId)) ||
      (need.posterId === voucheeId && acceptedResponderIds.includes(voucherId))
    if (!wereCounterparts) {
      return next(forbidden('You did not complete this need with that user', 'NOT_COUNTERPARTS'))
    }

    const voucheeProfile = await prisma.profile.findUnique({
      where: { userId: voucheeId },
      select: { skills: { select: { skill: { select: { id: true, label: true } } } } },
    })
    const candidateSkills = (voucheeProfile?.skills ?? []).map((s) => s.skill)

    const suggested = await suggestSkillsForCompletedNeed(need, candidateSkills)
    res.json({ suggestedSkills: suggested })
  } catch (err) { next(err) }
})
