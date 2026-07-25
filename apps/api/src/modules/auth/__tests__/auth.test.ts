import { describe, it, expect, afterAll } from 'vitest'
import request from 'supertest'
import jwt from 'jsonwebtoken'
import { app } from '../../../app'
import { prisma } from '../../../lib/prisma'

const RUN_ID = Date.now()
const email = (n: number) => `vitest-${RUN_ID}-${n}@needhub.dev`

const VALID_PASSWORD = 'Password123!'
const WEAK_PASSWORD = 'short'

let sharedToken: string
let sharedUserId: string

afterAll(async () => {
  await prisma.user.deleteMany({ where: { email: { contains: `vitest-${RUN_ID}` } } })
})

// ─── POST /auth/signup ───────────────────────────────────────────────────────

describe('POST /auth/signup', () => {
  it('201 — creates unverified user and returns userId + requiresVerification', async () => {
    const res = await request(app)
      .post('/auth/signup')
      .send({ email: email(1), password: VALID_PASSWORD, displayName: 'Alice' })

    expect(res.status).toBe(201)
    expect(res.body).toHaveProperty('userId')
    expect(res.body.requiresVerification).toBe(true)
    expect(res.body).not.toHaveProperty('token')

    sharedUserId = res.body.userId

    // User row exists but is unverified.
    const dbUser = await prisma.user.findUnique({ where: { id: sharedUserId } })
    expect(dbUser?.emailVerifiedAt).toBeNull()

    // A pending EmailVerification row was created.
    const pending = await prisma.emailVerification.findUnique({ where: { userId: sharedUserId } })
    expect(pending).not.toBeNull()
  })

  it('409 — duplicate email is rejected', async () => {
    const res = await request(app)
      .post('/auth/signup')
      .send({ email: email(1), password: VALID_PASSWORD, displayName: 'Alice Clone' })

    expect(res.status).toBe(409)
    expect(res.body.code).toBe('EMAIL_TAKEN')
  })

  it('400 — password too short', async () => {
    const res = await request(app)
      .post('/auth/signup')
      .send({ email: email(2), password: WEAK_PASSWORD, displayName: 'Bob' })
    expect(res.status).toBe(400)
  })

  it('400 — invalid email format', async () => {
    const res = await request(app)
      .post('/auth/signup')
      .send({ email: 'not-an-email', password: VALID_PASSWORD, displayName: 'Bob' })
    expect(res.status).toBe(400)
  })

  it('400 — displayName too short', async () => {
    const res = await request(app)
      .post('/auth/signup')
      .send({ email: email(3), password: VALID_PASSWORD, displayName: 'X' })
    expect(res.status).toBe(400)
  })

  it('profile row is auto-created with 0 points', async () => {
    const user = await prisma.user.findUnique({
      where: { id: sharedUserId },
      include: { profile: true },
    })
    expect(user?.profile).not.toBeNull()
    expect(user?.profile?.pointsTotal).toBe(0)
  })
})

// ─── POST /auth/verify-email ─────────────────────────────────────────────────

describe('POST /auth/verify-email', () => {
  it('400 — wrong code increments attempts', async () => {
    const before = await prisma.emailVerification.findUnique({ where: { userId: sharedUserId } })
    const res = await request(app)
      .post('/auth/verify-email')
      .send({ userId: sharedUserId, code: '111111' })
    expect(res.status).toBe(400)
    expect(res.body.code).toBe('OTP_INVALID')
    const after = await prisma.emailVerification.findUnique({ where: { userId: sharedUserId } })
    expect(after!.attempts).toBe(before!.attempts + 1)
  })

  it('400 — malformed code (not 6 digits) is rejected pre-DB', async () => {
    const res = await request(app)
      .post('/auth/verify-email')
      .send({ userId: sharedUserId, code: 'abc' })
    expect(res.status).toBe(400)
    expect(res.body.code).toBe('INVALID_BODY')
  })

  it('200 — dev bypass code 000000 verifies + returns JWT', async () => {
    const res = await request(app)
      .post('/auth/verify-email')
      .send({ userId: sharedUserId, code: '000000' })
    expect(res.status).toBe(200)
    expect(res.body).toHaveProperty('token')
    expect(res.body.user.id).toBe(sharedUserId)

    const payload = jwt.decode(res.body.token) as Record<string, unknown>
    expect(payload.sub).toBe(sharedUserId)
    expect(payload.email).toBe(email(1))

    sharedToken = res.body.token

    const dbUser = await prisma.user.findUnique({ where: { id: sharedUserId } })
    expect(dbUser?.emailVerifiedAt).not.toBeNull()
    const stillPending = await prisma.emailVerification.findUnique({ where: { userId: sharedUserId } })
    expect(stillPending).toBeNull()
  })
})

// ─── POST /auth/login ────────────────────────────────────────────────────────

describe('POST /auth/login', () => {
  it('200 — verified user with correct credentials returns token + userId', async () => {
    const res = await request(app)
      .post('/auth/login')
      .send({ email: email(1), password: VALID_PASSWORD })
    expect(res.status).toBe(200)
    expect(res.body.userId).toBe(sharedUserId)
    expect(typeof res.body.token).toBe('string')
  })

  it('403 EMAIL_NOT_VERIFIED — unverified user cannot log in', async () => {
    // Sign up a second user and try to log in without verifying.
    const signup = await request(app)
      .post('/auth/signup')
      .send({ email: email(4), password: VALID_PASSWORD, displayName: 'Carol' })
    expect(signup.status).toBe(201)

    const login = await request(app)
      .post('/auth/login')
      .send({ email: email(4), password: VALID_PASSWORD })
    expect(login.status).toBe(403)
    expect(login.body.code).toBe('EMAIL_NOT_VERIFIED')
  })

  it('401 — wrong password', async () => {
    const res = await request(app)
      .post('/auth/login')
      .send({ email: email(1), password: 'wrongpassword' })
    expect(res.status).toBe(401)
    expect(res.body.code).toBe('INVALID_CREDENTIALS')
  })

  it('401 — unknown email uses the same code as wrong password', async () => {
    const res = await request(app)
      .post('/auth/login')
      .send({ email: 'ghost@needhub.dev', password: VALID_PASSWORD })
    expect(res.status).toBe(401)
    expect(res.body.code).toBe('INVALID_CREDENTIALS')
  })
})

// ─── POST /auth/resend-otp ───────────────────────────────────────────────────

describe('POST /auth/resend-otp', () => {
  it('400 ALREADY_VERIFIED — resend on a verified account is rejected', async () => {
    const res = await request(app)
      .post('/auth/resend-otp')
      .send({ userId: sharedUserId })
    expect(res.status).toBe(400)
    expect(res.body.code).toBe('ALREADY_VERIFIED')
  })

  it('200 then 429 OTP_THROTTLED — second call within 60s is rejected', async () => {
    const signup = await request(app)
      .post('/auth/signup')
      .send({ email: email(5), password: VALID_PASSWORD, displayName: 'Dave' })
    const uid = signup.body.userId

    const first = await request(app).post('/auth/resend-otp').send({ userId: uid })
    expect(first.status).toBe(200)

    const second = await request(app).post('/auth/resend-otp').send({ userId: uid })
    expect(second.status).toBe(429)
    expect(second.body.code).toBe('OTP_THROTTLED')
  })
})

// ─── GET /auth/me ────────────────────────────────────────────────────────────

describe('GET /auth/me', () => {
  it('200 — returns user profile for valid token', async () => {
    const res = await request(app)
      .get('/auth/me')
      .set('Authorization', `Bearer ${sharedToken}`)
    expect(res.status).toBe(200)
    expect(res.body.id).toBe(sharedUserId)
    expect(res.body.email).toBe(email(1))
    expect(res.body.displayName).toBe('Alice')
    expect(res.body).not.toHaveProperty('passwordHash')
  })

  it('401 AUTH_REQUIRED — no Authorization header', async () => {
    const res = await request(app).get('/auth/me')
    expect(res.status).toBe(401)
    expect(res.body.code).toBe('AUTH_REQUIRED')
  })

  it('401 AUTH_REQUIRED — tampered token', async () => {
    const res = await request(app)
      .get('/auth/me')
      .set('Authorization', 'Bearer eyJhbGciOiJIUzI1NiJ9.fake.payload')
    expect(res.status).toBe(401)
    expect(res.body.code).toBe('AUTH_REQUIRED')
  })
})
