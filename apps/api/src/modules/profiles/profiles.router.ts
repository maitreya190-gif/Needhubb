import { Router, type IRouter } from 'express'
import multer from 'multer'
import { prisma } from '../../lib/prisma'
import { authenticate, type AuthedRequest } from '../../middleware/authenticate'
import { notFound, badRequest } from '../../lib/http-error'
import { uploadFile, deleteFile, storageKey } from '../../lib/storage'

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
    res.json(user)
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

// ── GET /profile/search?q=  ───────────────────────────────────────────────────
// Simple substring match on displayName + email. Used by the chats-tab search
// sheet to find users to friend. Excludes self and blocked users.

profilesRouter.get('/search', authenticate, async (req, res, next) => {
  try {
    const me = (req as AuthedRequest).userId!
    const raw = ((req.query.q as string) ?? '').trim()
    if (raw.length < 1) return res.json([])
    const users = await prisma.user.findMany({
      where: {
        AND: [
          { id: { not: me } },
          { username: { contains: raw, mode: 'insensitive' } },
        ],
      },
      select: {
        id: true, username: true, displayName: true, email: true,
        profile: { select: { avatarUrl: true, bio: true } },
      },
      take: 20,
      orderBy: { displayName: 'asc' },
    })
    res.json(users)
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
    res.json(user)
  } catch (err) { next(err) }
})
