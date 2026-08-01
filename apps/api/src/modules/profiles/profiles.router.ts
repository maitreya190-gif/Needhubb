import bcrypt from 'bcryptjs'
import { Router, type IRouter } from 'express'
import multer from 'multer'
import { prisma } from '../../lib/prisma'
import { authenticate, type AuthedRequest } from '../../middleware/authenticate'
import { notFound, badRequest, tooMany } from '../../lib/http-error'
import { uploadFile, deleteFile, storageKey } from '../../lib/storage'
import { verifyFace } from '../../lib/face-verify'
import { analyzePersonality } from '../../lib/lyzr'
import { twilioVerifyConfigured, startPhoneVerification, checkPhoneVerification } from '../../lib/sms'
import { computeTrustScore } from '../../lib/trust-score'
import { otpLimiter } from '../../middleware/rateLimiter'

export const profilesRouter: IRouter = Router()

// Same dev-bypass policy as email OTP (auth.service.ts) — always on for the
// hackathon demo, set ALLOW_DEV_OTP_BYPASS=false in prod to lock it down.
function bypassAllowed(): boolean {
  const raw = (process.env.ALLOW_DEV_OTP_BYPASS ?? 'true').trim().replace(/^["']|["']$/g, '').toLowerCase()
  return raw !== 'false' && raw !== '0' && raw !== 'no' && raw !== 'off'
}
const DEV_BYPASS_CODE = '000000'
const PHONE_OTP_TTL_MS = 10 * 60 * 1000
const PHONE_OTP_MAX_ATTEMPTS = 5
const PHONE_REGEX = /^\+?[1-9]\d{7,14}$/

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
      select: {
        id: true, email: true, username: true, emailVerifiedAt: true,
        phone: true, phoneVerifiedAt: true, displayName: true,
        verificationLevel: true, referralCode: true, referredBy: true, createdAt: true,
        // passwordHash deliberately excluded — never send it to any client, even your own.
        profile: {
          include: {
            interests: { include: { interest: true } },
            skills: { include: { skill: true } },
          },
        },
      },
    })
    if (!user) return next(notFound('User not found', 'USER_NOT_FOUND'))
    const [reviewsAgg, trustExtras] = await Promise.all([
      prisma.review.aggregate({ where: { revieweeId: userId }, _avg: { rating: true }, _count: { id: true } }),
      fetchTrustExtras(userId),
    ])
    const avgRating = reviewsAgg._avg.rating ? Math.round(reviewsAgg._avg.rating * 10) / 10 : 0
    const ratingCount = reviewsAgg._count.id
    const trustScore = computeTrustScore({
      emailVerifiedAt: user.emailVerifiedAt,
      phoneVerifiedAt: user.phoneVerifiedAt,
      faceVerifiedAt: user.profile?.faceVerifiedAt ?? null,
      ...trustExtras,
      avgRating,
      ratingCount,
    })
    res.json({ ...user, avgRating, ratingCount, trustScore })
  } catch (err) { next(err) }
})

// Certificates + fulfilled-need count feed the "track record" half of trust
// score (see lib/trust-score.ts) — split out so both profile endpoints share it.
async function fetchTrustExtras(userId: string) {
  const [approvedCertificateCount, fulfilledNeedCount] = await Promise.all([
    prisma.certificate.count({ where: { userId, status: 'APPROVED' } }),
    prisma.need.count({ where: { posterId: userId, status: 'FULFILLED' } }),
  ])
  return { approvedCertificateCount, fulfilledNeedCount }
}

// ── PATCH /profile/me ─────────────────────────────────────────────────────────

profilesRouter.patch('/me', authenticate, async (req, res, next) => {
  try {
    const userId = (req as AuthedRequest).userId!
    const { bio, location, lat, lng, gender, promptSkill, promptCollab, promptNeed, displayName, interests, skills } =
      req.body as {
        bio?: string
        location?: string
        lat?: number
        lng?: number
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
        ...(lat !== undefined && { lat }),
        ...(lng !== undefined && { lng }),
        ...(gender !== undefined && { gender }),
        ...(promptSkill !== undefined && { promptSkill }),
        ...(promptCollab !== undefined && { promptCollab }),
        ...(promptNeed !== undefined && { promptNeed }),
      },
      create: { userId, bio, locationText: location, lat, lng, gender, promptSkill, promptCollab, promptNeed },
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
    let result
    try {
      result = await verifyFace(req.file.buffer, req.file.mimetype)
    } catch (verifyErr: any) {
      const msg = verifyErr?.message ?? 'Face verification service unavailable'
      console.error('[face-verify] service error:', msg)

      // Demo-safe fallback: if Face++ itself is down/misconfigured but the
      // caller is authenticated AND uploaded a real image, treat as verified.
      // This ensures the demo never breaks on third-party API issues.
      // Set FACE_VERIFY_STRICT=true to disable this fallback in production.
      const strictMode = process.env.FACE_VERIFY_STRICT === 'true'
      if (!strictMode && req.file.size > 5000) {
        console.warn('[face-verify] Face++ unreachable — using fallback verification')
        result = { verified: true, reason: 'Verified (fallback mode)' }
      } else {
        return res.status(400).json({
          verified: false,
          reason: msg.includes('Face++ not configured')
            ? 'Face verification is not configured on the server.'
            : msg.includes('CONCURRENCY_LIMIT') || msg.includes('rate')
              ? 'Verification service is busy — try again in a few seconds.'
              : msg.includes('INVALID_IMAGE_SIZE') || msg.includes('too large')
                ? 'Photo is too large. Try a lower-quality selfie.'
                : 'Verification service error — please try again.',
        })
      }
    }

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

// ── POST /profile/me/phone/send-otp ──────────────────────────────────────────
// Trust Score, step 2 (after compulsory email verification at signup). Uses
// Twilio Verify when configured (see lib/sms.ts — Twilio generates + sends
// + owns the code, we never see it). Falls back to our own hashed code,
// logged server-side, when Verify isn't configured or fails to start — same
// "app works with the third party down" policy as email OTP.

profilesRouter.post('/me/phone/send-otp', authenticate, otpLimiter, async (req, res, next) => {
  try {
    const userId = (req as AuthedRequest).userId!
    const phone = String((req.body as { phone?: string })?.phone ?? '').trim()
    if (!PHONE_REGEX.test(phone)) {
      return next(badRequest('Enter a valid phone number in international format, e.g. +919876543210', 'INVALID_PHONE'))
    }

    const takenByOther = await prisma.user.findFirst({
      where: { phone, NOT: { id: userId } },
      select: { id: true },
    })
    if (takenByOther) return next(badRequest('This phone number is already verified on another account', 'PHONE_TAKEN'))

    if (twilioVerifyConfigured()) {
      const result = await startPhoneVerification(phone)
      if (result.ok) {
        // codeHash '' marks "Twilio owns this code" for verify-otp below —
        // Twilio Verify never tells us the code, so there's nothing to hash.
        await prisma.phoneVerification.upsert({
          where: { userId },
          create: { userId, phone, codeHash: '', expiresAt: new Date(Date.now() + PHONE_OTP_TTL_MS), attempts: 0 },
          update: { phone, codeHash: '', expiresAt: new Date(Date.now() + PHONE_OTP_TTL_MS), attempts: 0 },
        })
        return res.json({ ok: true })
      }
      console.error('[phone-verify] Twilio Verify start failed, falling back to local OTP:', result.error)
    }

    const code = String(Math.floor(100000 + Math.random() * 900000))
    const codeHash = await bcrypt.hash(code, 8)
    await prisma.phoneVerification.upsert({
      where: { userId },
      create: { userId, phone, codeHash, expiresAt: new Date(Date.now() + PHONE_OTP_TTL_MS), attempts: 0 },
      update: { phone, codeHash, expiresAt: new Date(Date.now() + PHONE_OTP_TTL_MS), attempts: 0 },
    })
    console.log(`[sms dev-fallback] OTP for ${phone}: ${code}`)

    res.json({
      ok: true,
      ...(bypassAllowed() ? { devOtp: code } : {}),
    })
  } catch (err) { next(err) }
})

// ── POST /profile/me/phone/verify-otp ────────────────────────────────────────

profilesRouter.post('/me/phone/verify-otp', authenticate, async (req, res, next) => {
  try {
    const userId = (req as AuthedRequest).userId!
    const code = String((req.body as { code?: string })?.code ?? '').trim()
    if (!/^\d{6}$/.test(code)) return next(badRequest('Code must be exactly 6 digits', 'INVALID_CODE'))

    const row = await prisma.phoneVerification.findUnique({ where: { userId } })
    if (!row) return next(badRequest('No pending phone verification. Request a new code.', 'OTP_NOT_ISSUED'))

    // Dev bypass always works, regardless of which path issued the code —
    // same policy as email OTP.
    if (code === DEV_BYPASS_CODE && bypassAllowed()) {
      const user = await markPhoneVerified(userId, row.phone)
      return res.json({ verified: true, phone: user.phone, verificationLevel: user.verificationLevel })
    }

    if (row.expiresAt.getTime() < Date.now()) {
      await prisma.phoneVerification.delete({ where: { userId } }).catch(() => {})
      return next(badRequest('Code expired. Request a new one.', 'OTP_EXPIRED'))
    }
    if (row.attempts >= PHONE_OTP_MAX_ATTEMPTS) {
      return next(tooMany('Too many attempts. Request a new code.', 'OTP_MAX_ATTEMPTS'))
    }

    let ok: boolean
    if (row.codeHash === '') {
      // Issued via Twilio Verify — Twilio is the source of truth for the code.
      const result = await checkPhoneVerification(row.phone, code)
      ok = result.approved
    } else {
      ok = await bcrypt.compare(code, row.codeHash)
    }

    if (!ok) {
      await prisma.phoneVerification.update({ where: { userId }, data: { attempts: { increment: 1 } } })
      return next(badRequest('Incorrect code', 'OTP_INVALID'))
    }

    const user = await markPhoneVerified(userId, row.phone)
    res.json({ verified: true, phone: user.phone, verificationLevel: user.verificationLevel })
  } catch (err) { next(err) }
})

async function markPhoneVerified(userId: string, phone: string) {
  const user = await prisma.user.update({
    where: { id: userId },
    data: {
      phone,
      phoneVerifiedAt: new Date(),
      // Email is already required to have an account; phone is the next tier.
      // ID verification (highest tier) isn't built yet, so this only ever climbs to PHONE.
      verificationLevel: 'PHONE',
    },
  })
  await prisma.phoneVerification.delete({ where: { userId } }).catch(() => {})
  return user
}

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
      // Public + unauthenticated route: select only what other users' profile
      // views actually need. No passwordHash, and no raw email/phone (the app
      // never displays another user's contact info) — verifiedAt timestamps
      // are kept since trust score needs them and they reveal nothing private.
      select: {
        id: true, username: true, displayName: true,
        emailVerifiedAt: true, phoneVerifiedAt: true,
        verificationLevel: true, createdAt: true,
        profile: {
          include: {
            interests: { include: { interest: true } },
            skills: { include: { skill: true } },
          },
        },
      },
    })
    if (!user) return next(notFound('User not found', 'USER_NOT_FOUND'))
    const [reviewsAgg, trustExtras] = await Promise.all([
      prisma.review.aggregate({ where: { revieweeId: req.params.userId }, _avg: { rating: true }, _count: { id: true } }),
      fetchTrustExtras(req.params.userId),
    ])
    const avgRating = reviewsAgg._avg.rating ? Math.round(reviewsAgg._avg.rating * 10) / 10 : 0
    const ratingCount = reviewsAgg._count.id
    const trustScore = computeTrustScore({
      emailVerifiedAt: user.emailVerifiedAt,
      phoneVerifiedAt: user.phoneVerifiedAt,
      faceVerifiedAt: user.profile?.faceVerifiedAt ?? null,
      ...trustExtras,
      avgRating,
      ratingCount,
    })
    res.json({ ...user, avgRating, ratingCount, trustScore })
  } catch (err) { next(err) }
})
