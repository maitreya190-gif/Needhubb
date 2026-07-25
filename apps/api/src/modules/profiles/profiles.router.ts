import { Router, type IRouter } from 'express'
import multer from 'multer'
import { prisma } from '../../lib/prisma'
import { authenticate, type AuthedRequest } from '../../middleware/authenticate'
import { notFound, badRequest } from '../../lib/http-error'
import { uploadFile, deleteFile, storageKey } from '../../lib/storage'
import { verifyFace } from '../../lib/face-verify'
import { analyzePersonality } from '../../lib/lyzr'

export const profilesRouter: IRouter = Router()

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (!file.mimetype.startsWith('image/')) cb(new Error('Images only'))
    else cb(null, true)
  },
})

// ── GET /profile/me ───────────────────────────────────────────────────────────

profilesRouter.get('/me', authenticate, async (req, res, next) => {
  try {
    const userId = (req as AuthedRequest).userId!
    const user = await prisma.user.findUnique({
      where: { id: userId },
      include: {
        profile: {
          include: {
            interests: { include: { interest: true } },
            skills: { include: { skill: true } },
          },
        },
      },
    })
    if (!user) return next(notFound('User not found', 'USER_NOT_FOUND'))
    const reviewsAgg = await prisma.review.aggregate({
      where: { revieweeId: userId },
      _avg: { rating: true },
      _count: { id: true },
    })
    const avgRating = reviewsAgg._avg.rating ? Math.round(reviewsAgg._avg.rating * 10) / 10 : 0
    const ratingCount = reviewsAgg._count.id
    res.json({ ...user, avgRating, ratingCount })
  } catch (err) { next(err) }
})

// ── PATCH /profile/me ─────────────────────────────────────────────────────────

profilesRouter.patch('/me', authenticate, async (req, res, next) => {
  try {
    const userId = (req as AuthedRequest).userId!
    const { bio, location, gender, promptSkill, promptCollab, promptNeed, displayName, interests, skills } =
      req.body as {
        bio?: string
        location?: string
        gender?: string
        promptSkill?: string
        promptCollab?: string
        promptNeed?: string
        displayName?: string
        interests?: string[]
        skills?: string[]
      }

    if (displayName !== undefined) {
      await prisma.user.update({ where: { id: userId }, data: { displayName } })
    }

    const profile = await prisma.profile.upsert({
      where: { userId },
      update: {
        ...(bio !== undefined && { bio }),
        ...(location !== undefined && { locationText: location }),
        ...(gender !== undefined && { gender }),
        ...(promptSkill !== undefined && { promptSkill }),
        ...(promptCollab !== undefined && { promptCollab }),
        ...(promptNeed !== undefined && { promptNeed }),
      },
      create: { userId, bio, locationText: location, gender, promptSkill, promptCollab, promptNeed },
    })

    if (Array.isArray(interests)) {
      const uniqueLabels = Array.from(new Set(interests.map(i => i.trim()).filter(Boolean)))
      const interestRecords = await Promise.all(
        uniqueLabels.map(label =>
          prisma.interest.upsert({
            where: { label },
            update: {},
            create: { label },
          })
        )
      )
      await prisma.profileInterest.deleteMany({ where: { profileId: profile.id } })
      if (interestRecords.length > 0) {
        await prisma.profileInterest.createMany({
          data: interestRecords.map(ir => ({
            profileId: profile.id,
            interestId: ir.id,
          })),
          skipDuplicates: true,
        })
      }
    }

    if (Array.isArray(skills)) {
      const uniqueLabels = Array.from(new Set(skills.map(s => s.trim()).filter(Boolean)))
      const skillRecords = await Promise.all(
        uniqueLabels.map(label =>
          prisma.skill.upsert({
            where: { label },
            update: {},
            create: { label },
          })
        )
      )
      await prisma.profileSkill.deleteMany({ where: { profileId: profile.id } })
      if (skillRecords.length > 0) {
        await prisma.profileSkill.createMany({
          data: skillRecords.map(sr => ({
            profileId: profile.id,
            skillId: sr.id,
          })),
          skipDuplicates: true,
        })
      }
    }

    const updatedUser = await prisma.user.findUnique({
      where: { id: userId },
      include: {
        profile: {
          include: {
            interests: { include: { interest: true } },
            skills: { include: { skill: true } },
          },
        },
      },
    })
    res.json(updatedUser)
  } catch (err) { next(err) }
})

// ── POST /profile/me/avatar ───────────────────────────────────────────────────

profilesRouter.post('/me/avatar', authenticate, upload.single('file'), async (req, res, next) => {
  try {
    const userId = (req as AuthedRequest).userId!
    if (!req.file) return next(badRequest('Image file required', 'FILE_REQUIRED'))

    const key = storageKey(`avatars/${userId}`, req.file.originalname)
    const avatarUrl = await uploadFile(key, req.file.buffer, req.file.mimetype)

    const profile = await prisma.profile.upsert({
      where: { userId },
      update: { avatarUrl },
      create: { userId, avatarUrl },
    })
    res.json({ avatarUrl: profile.avatarUrl })
  } catch (err) { next(err) }
})

// ── DELETE /profile/me/avatar ─────────────────────────────────────────────────

profilesRouter.delete('/me/avatar', authenticate, async (req, res, next) => {
  try {
    const userId = (req as AuthedRequest).userId!
    const profile = await prisma.profile.findUnique({ where: { userId }, select: { avatarUrl: true } })
    if (profile?.avatarUrl) {
      const key = profile.avatarUrl.split('/uploads/')[1]
      if (key) await deleteFile(key)
    }
    await prisma.profile.update({ where: { userId }, data: { avatarUrl: null } })
    res.json({ ok: true })
  } catch (err) { next(err) }
})

// ── POST /profile/me/face-verify ─────────────────────────────────────────────

profilesRouter.post('/me/face-verify', authenticate, upload.single('selfie'), async (req, res, next) => {
  try {
    const userId = (req as AuthedRequest).userId!
    if (!req.file) return next(badRequest('No image uploaded', 'NO_IMAGE'))

    // Process in memory only — image is never written to disk
    const result = await verifyFace(req.file.buffer, req.file.mimetype)

    if (!result.verified) {
      return res.status(400).json({ verified: false, reason: result.reason })
    }

    await prisma.profile.upsert({
      where: { userId },
      update: { faceVerifiedAt: new Date() },
      create: { userId, faceVerifiedAt: new Date() },
    })

    // Image buffer is dereferenced here — never stored
    res.json({ verified: true })
  } catch (err) { next(err) }
})

// ── POST /profile/me/personality ─────────────────────────────────────────────
// Accepts 10 quiz answers, sends them to the Lyzr personality analyzer agent,
// and stores the resulting profile so we can compute compatibility % between
// users on the Connect surface.

profilesRouter.post('/me/personality', authenticate, async (req, res, next) => {
  try {
    const userId = (req as AuthedRequest).userId!
    const body = req.body as { answers?: unknown }
    if (!Array.isArray(body.answers) || body.answers.length !== 10) {
      return next(badRequest('Exactly 10 answers required', 'INVALID_ANSWERS'))
    }
    const answers = body.answers.map((a) => String(a ?? '').trim()).filter(Boolean)
    if (answers.length !== 10) {
      return next(badRequest('All 10 answers must be non-empty', 'INVALID_ANSWERS'))
    }

    // One-shot: refuse if the user has already taken the test.
    const existing = await prisma.profile.findUnique({
      where: { userId },
      select: { personalityTakenAt: true },
    })
    if (existing?.personalityTakenAt) {
      return next(badRequest('Personality test already taken', 'ALREADY_TAKEN'))
    }

    // analyzePersonality has a guaranteed local fallback so it never
    // throws — the tier-3 Big-Five scoring engine runs offline and
    // always returns a valid profile even if Lyzr and Groq are both down.
    const profile = await analyzePersonality(answers)

    // Persist only the DB-shape (strip the `poweredBy` badge before writing).
    const dbFields = {
      personalityTraits: profile.traits,
      personalityNickname: profile.nickname,
      personalitySummary: profile.summary,
      personalityVibeTags: profile.vibeTags,
      personalityTakenAt: new Date(),
    }
    await prisma.profile.upsert({
      where: { userId },
      update: dbFields,
      create: { userId, ...dbFields },
    })

    res.json(profile)
  } catch (err) { next(err) }
})

// ── GET /profile/search?q=  ───────────────────────────────────────────────────
// Simple substring match on displayName + email. Used by the chats-tab search
// sheet to find users to friend. Excludes self and blocked users.

profilesRouter.get('/search', authenticate, async (req, res, next) => {
  try {
    const me = (req as AuthedRequest).userId!
    const raw = ((req.query.q as string) ?? '').trim().replace(/^@/, '')
    if (raw.length < 1) return res.json([])
    const users = await prisma.user.findMany({
      where: {
        AND: [
          { id: { not: me } },
          {
            OR: [
              { username: { contains: raw, mode: 'insensitive' } },
              { displayName: { contains: raw, mode: 'insensitive' } },
            ],
          },
        ],
      },
      select: {
        id: true,
        username: true,
        displayName: true,
        profile: { select: { avatarUrl: true, bio: true } },
      },
      take: 20,
      orderBy: { displayName: 'asc' },
    })
    // Ensure every result has a handle — derive one from displayName if username is null
    const result = users.map(u => ({
      ...u,
      username: u.username ?? u.displayName.toLowerCase().replace(/\s+/g, '_').replace(/[^a-z0-9_]/g, ''),
    }))
    res.json(result)
  } catch (err) { next(err) }
})

// ── GET /profile/:userId  [public] ────────────────────────────────────────────

profilesRouter.get('/:userId', async (req, res, next) => {
  try {
    const user = await prisma.user.findUnique({
      where: { id: req.params.userId },
      include: {
        profile: {
          include: {
            interests: { include: { interest: true } },
            skills: { include: { skill: true } },
          },
        },
      },
    })
    if (!user) return next(notFound('User not found', 'USER_NOT_FOUND'))
    const reviewsAgg = await prisma.review.aggregate({
      where: { revieweeId: req.params.userId },
      _avg: { rating: true },
      _count: { id: true },
    })
    const avgRating = reviewsAgg._avg.rating ? Math.round(reviewsAgg._avg.rating * 10) / 10 : 0
    const ratingCount = reviewsAgg._count.id
    res.json({ ...user, avgRating, ratingCount })
  } catch (err) { next(err) }
})
