import bcrypt from 'bcryptjs'
import jwt from 'jsonwebtoken'
import { prisma } from '../../lib/prisma'
import { config } from '../../config'
import { sendOtp } from '../../lib/email'
import {
  badRequest, conflict, forbidden, notFound, tooMany, unauthorized,
} from '../../lib/http-error'
import type { SignupBody, LoginBody, VerifyEmailBody, ResendOtpBody } from './auth.schemas'

const SALT_ROUNDS = 12
const TOKEN_TTL = '7d'
const OTP_TTL_MS = 10 * 60 * 1000
const OTP_MAX_ATTEMPTS = 5
const RESEND_THROTTLE_MS = 60 * 1000
const DEV_BYPASS_CODE = '000000'

// In-memory throttle. Fine for a single-instance hackathon deploy.
// For multi-instance prod, move to Redis or a DB column.
const lastResendAt = new Map<string, number>()

function generateOtp(): string {
  return String(Math.floor(100000 + Math.random() * 900000))
}

async function issueOtp(userId: string, email: string, waitForEmail = false): Promise<string> {
  const code = generateOtp()
  const codeHash = await bcrypt.hash(code, 8)
  await prisma.emailVerification.upsert({
    where: { userId },
    create: {
      userId,
      codeHash,
      expiresAt: new Date(Date.now() + OTP_TTL_MS),
      attempts: 0,
    },
    update: {
      codeHash,
      expiresAt: new Date(Date.now() + OTP_TTL_MS),
      attempts: 0,
    },
  })
  // Fire-and-forget by default so signup doesn't hang if Gmail/Resend is slow
  // or unreachable. The OTP is already persisted, so users can enter it as
  // soon as it arrives OR use the dev bypass 000000.
  const emailPromise = sendOtp(email, code).catch((err) =>
    console.error('[auth] sendOtp failed:', (err as Error).message),
  )
  if (waitForEmail) await emailPromise
  return code
}

function bypassAllowed(): boolean {
  // Always on for the hackathon demo. Set ALLOW_DEV_OTP_BYPASS=false explicitly
  // in production to lock it down after the demo.
  const raw = (process.env.ALLOW_DEV_OTP_BYPASS ?? 'true').trim().replace(/^["']|["']$/g, '').toLowerCase()
  return raw !== 'false' && raw !== '0' && raw !== 'no' && raw !== 'off'
}

function generateReferralCode(displayName: string): string {
  const prefix = displayName.replace(/[^a-zA-Z]/g, '').slice(0, 3).toUpperCase()
  const suffix = Math.random().toString(36).substring(2, 5).toUpperCase()
  return (prefix + suffix).padEnd(6, 'X').slice(0, 6)
}

export async function uniqueReferralCode(displayName: string): Promise<string> {
  for (let i = 0; i < 10; i++) {
    const code = generateReferralCode(displayName)
    const existing = await prisma.user.findUnique({ where: { referralCode: code } })
    if (!existing) return code
  }
  return Math.random().toString(36).substring(2, 8).toUpperCase()
}

export async function signup({ email, password, displayName, username, referralCode }: SignupBody) {
  const existing = await prisma.user.findUnique({ where: { email } })
  if (existing) throw conflict('Email already registered', 'EMAIL_TAKEN')

  if (username) {
    const taken = await prisma.user.findUnique({ where: { username } })
    if (taken) throw conflict('Username already taken', 'USERNAME_TAKEN')
  }

  // Validate referral code if provided — resolve to referrer id
  let referrerId: string | null = null
  if (referralCode) {
    const referrer = await prisma.user.findUnique({ where: { referralCode: referralCode.toUpperCase() } })
    if (referrer) referrerId = referrer.id
    // Silently ignore invalid codes — it's optional
  }

  const myReferralCode = await uniqueReferralCode(displayName)
  const passwordHash = await bcrypt.hash(password, SALT_ROUNDS)
  const user = await prisma.user.create({
    data: {
      email,
      passwordHash,
      displayName,
      username: username ?? null,
      emailVerifiedAt: null,
      referralCode: myReferralCode,
      referredBy: referrerId,
      profile: { create: {} },
    },
  })

  // Create a PENDING referral record so the referrer can track it
  if (referrerId) {
    await prisma.referral.create({
      data: { referrerId, refereeId: user.id },
    })
  }

  const otp = await issueOtp(user.id, user.email)
  return {
    userId: user.id,
    requiresVerification: true as const,
    ...(bypassAllowed() ? { devOtp: otp } : {}),
  }
}

export async function verifyEmail({ userId, code }: VerifyEmailBody) {
  const user = await prisma.user.findUnique({ where: { id: userId } })
  if (!user) throw notFound('User not found', 'USER_NOT_FOUND')
  if (user.emailVerifiedAt) {
    // Never issue a token just because the account happens to already be
    // verified — userId is not secret (it's returned by public profile
    // endpoints), so this would let anyone mint a token for any verified
    // account with no proof of code/password. Match resendOtp's convention:
    // error out, the client should sign in via /auth/login instead.
    throw badRequest('Already verified', 'ALREADY_VERIFIED')
  }

  // Dev bypass — accepts the fixed code 000000 in demo mode.
  if (code === DEV_BYPASS_CODE && bypassAllowed()) {
    const updated = await markVerified(userId)
    return { token: signToken(updated.id, updated.email), user: publicUser(updated) }
  }

  const row = await prisma.emailVerification.findUnique({ where: { userId } })
  if (!row) throw badRequest('No pending verification. Request a new code.', 'OTP_NOT_ISSUED')
  if (row.expiresAt.getTime() < Date.now()) {
    await prisma.emailVerification.delete({ where: { userId } }).catch(() => {})
    throw badRequest('Code expired. Request a new one.', 'OTP_EXPIRED')
  }
  if (row.attempts >= OTP_MAX_ATTEMPTS) {
    throw tooMany('Too many attempts. Request a new code.', 'OTP_MAX_ATTEMPTS')
  }

  const ok = await bcrypt.compare(code, row.codeHash)
  if (!ok) {
    await prisma.emailVerification.update({
      where: { userId },
      data: { attempts: { increment: 1 } },
    })
    throw badRequest('Incorrect code', 'OTP_INVALID')
  }

  const updated = await markVerified(userId)
  return { token: signToken(updated.id, updated.email), user: publicUser(updated) }
}

async function markVerified(userId: string) {
  const updated = await prisma.user.update({
    where: { id: userId },
    data: { emailVerifiedAt: new Date() },
  })
  await prisma.emailVerification.delete({ where: { userId } }).catch(() => {})
  lastResendAt.delete(userId)
  return updated
}

export async function resendOtp({ userId }: ResendOtpBody) {
  const user = await prisma.user.findUnique({ where: { id: userId } })
  if (!user) throw notFound('User not found', 'USER_NOT_FOUND')
  if (user.emailVerifiedAt) throw badRequest('Already verified', 'ALREADY_VERIFIED')

  const last = lastResendAt.get(userId)
  if (last && Date.now() - last < RESEND_THROTTLE_MS) {
    const wait = Math.ceil((RESEND_THROTTLE_MS - (Date.now() - last)) / 1000)
    throw tooMany(`Please wait ${wait}s before requesting another code`, 'OTP_THROTTLED')
  }
  lastResendAt.set(userId, Date.now())

  const otp = await issueOtp(user.id, user.email)
  return {
    ok: true,
    ...(bypassAllowed() ? { devOtp: otp } : {}),
  }
}

export async function login({ email, password }: LoginBody) {
  const user = await prisma.user.findUnique({ where: { email } })
  const valid = user ? await bcrypt.compare(password, user.passwordHash) : false
  if (!user || !valid) throw unauthorized('Invalid credentials', 'INVALID_CREDENTIALS')

  if (!user.emailVerifiedAt) {
    // 403 with the userId payload so the mobile app can bounce the user back to the OTP screen.
    throw forbidden('Email not verified', 'EMAIL_NOT_VERIFIED')
  }

  return { token: signToken(user.id, user.email), userId: user.id }
}

export async function getMe(userId: string) {
  return prisma.user.findUniqueOrThrow({
    where: { id: userId },
    select: {
      id: true,
      email: true,
      displayName: true,
      verificationLevel: true,
      createdAt: true,
      profile: {
        select: {
          bio: true,
          locationText: true,
          pointsTotal: true,
        },
      },
    },
  })
}

function signToken(userId: string, email: string): string {
  return jwt.sign({ sub: userId, email }, config.authSecret, { expiresIn: TOKEN_TTL })
}

function publicUser(u: { id: string; email: string; displayName: string; verificationLevel: string; createdAt: Date }) {
  return {
    id: u.id, email: u.email, displayName: u.displayName,
    verificationLevel: u.verificationLevel, createdAt: u.createdAt,
  }
}
