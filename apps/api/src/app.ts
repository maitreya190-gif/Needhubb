import 'dotenv/config'
import path from 'node:path'
import express, { Router, type Express, type Router as ExpressRouter } from 'express'
import { authRouter } from './modules/auth/auth.router'
import { adminRouter } from './modules/admin/admin.router'
import { needsRouter } from './modules/needs/needs.router'
import { reportsRouter } from './modules/reports/reports.router'
import { certificatesRouter } from './modules/certificates/certificates.router'
import { profilesRouter } from './modules/profiles/profiles.router'
import { messagingRouter } from './modules/messaging/messaging.router'
import { friendsRouter } from './modules/friends/friends.router'
import { chitchatRouter } from './modules/chitchat/chitchat.router'
import { notificationsRouter } from './modules/notifications/notifications.router'
import { reviewsRouter } from './modules/reviews/reviews.router'
import { redemptionsRouter } from './modules/redemptions/redemptions.router'
import { achievementsRouter } from './modules/achievements/achievements.router'
import { adminAuth } from './middleware/adminAuth'
import { authenticate } from './middleware/authenticate'
import { errorHandler } from './middleware/errorHandler'
import { authLimiter, otpLimiter, writeLimiter, uploadLimiter, messagingLimiter } from './middleware/rateLimiter'
import { config } from './config'

export const app: Express = express()
app.set('trust proxy', 1)
app.use(express.json())

app.use((req, res, next) => {
  const origin = req.headers.origin ?? ''
  const allowed = config.corsOrigin === '*' || config.corsOrigin.split(',').map(s => s.trim()).includes(origin)
  if (allowed) res.setHeader('Access-Control-Allow-Origin', config.corsOrigin === '*' ? '*' : origin)
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PATCH,DELETE,OPTIONS')
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type,x-admin-secret,Authorization')
  if (req.method === 'OPTIONS') { res.sendStatus(204); return }
  next()
})

// Uploads: served statically. In dev, storage.ts writes files under apps/api/uploads/.
// In prod (R2 configured), this mount is dead weight — public URLs point at the R2 bucket.
app.use('/uploads', express.static(path.join(__dirname, '..', 'uploads')))

app.get('/health', (_req, res) => res.json({ ok: true }))

// Diagnostic: test Brevo HTTPS API. Returns exact error text.
// Usage: GET /admin/email-diag-brevo?to=friend@gmail.com  (needs x-admin-secret)
app.get('/admin/email-diag-brevo', adminAuth, async (req, res) => {
  try {
    const to = String(req.query.to || '')
    if (!to) return res.status(400).json({ error: 'pass ?to=someone@gmail.com' })

    const stripEnv = (v: string | undefined) =>
      (v ?? '').trim().replace(/^["']|["']$/g, '').trim()

    const key = stripEnv(process.env.BREVO_API_KEY)
    const fromRaw = stripEnv(process.env.EMAIL_FROM) || 'NeedHub <onboarding@needhub.app>'
    const match = fromRaw.match(/^\s*(.*?)\s*<([^>]+)>\s*$/)
    const senderName = match ? match[1] : 'NeedHub'
    const senderEmail = match ? match[2] : fromRaw

    if (!key) return res.json({ ok: false, error: 'BREVO_API_KEY not set' })

    const start = Date.now()
    try {
      const r = await fetch('https://api.brevo.com/v3/smtp/email', {
        method: 'POST',
        headers: {
          'api-key': key,
          'content-type': 'application/json',
          accept: 'application/json',
        },
        body: JSON.stringify({
          sender: { name: senderName, email: senderEmail },
          to: [{ email: to }],
          subject: 'NeedHub Brevo diagnostic',
          textContent: 'If you got this, Brevo delivery works from Railway.',
        }),
      })
      const body = await r.text()
      res.json({
        ok: r.ok,
        elapsed: Date.now() - start,
        status: r.status,
        from: `${senderName} <${senderEmail}>`,
        to,
        response: body.slice(0, 500),
      })
    } catch (err: any) {
      res.json({ ok: false, elapsed: Date.now() - start, error: err?.message ?? String(err) })
    }
  } catch (err: any) {
    res.status(500).json({ error: err?.message ?? 'unknown' })
  }
})

// Diagnostic: test Resend HTTPS API delivery. Returns exact error text.
// Usage: GET /admin/email-diag-resend?to=friend@gmail.com  (needs x-admin-secret)
app.get('/admin/email-diag-resend', adminAuth, async (req, res) => {
  try {
    const { Resend } = await import('resend')
    const to = String(req.query.to || '')
    if (!to) return res.status(400).json({ error: 'pass ?to=someone@gmail.com' })

    const stripEnv = (v: string | undefined) =>
      (v ?? '').trim().replace(/^["']|["']$/g, '').trim()

    const resendKey = stripEnv(process.env.RESEND_API_KEY)
    const from = stripEnv(process.env.EMAIL_FROM) || 'NeedHub <onboarding@resend.dev>'

    if (!resendKey) {
      return res.json({ ok: false, error: 'RESEND_API_KEY not set' })
    }

    const resend = new Resend(resendKey)
    const start = Date.now()
    try {
      const { data, error } = await resend.emails.send({
        from,
        to,
        subject: 'NeedHub Resend diagnostic',
        text: 'If you got this, Resend HTTPS delivery is working.',
      })
      if (error) {
        return res.json({
          ok: false,
          elapsed: Date.now() - start,
          from,
          to,
          error: JSON.stringify(error),
          hint: 'If sandbox — you can only send to the email that owns the Resend account, OR verify a domain in resend.com dashboard.',
        })
      }
      res.json({
        ok: true,
        elapsed: Date.now() - start,
        from,
        to,
        id: data?.id,
      })
    } catch (err: any) {
      res.json({
        ok: false,
        elapsed: Date.now() - start,
        from,
        to,
        error: err?.message ?? String(err),
      })
    }
  } catch (err: any) {
    res.status(500).json({ error: err?.message ?? 'unknown' })
  }
})

// Diagnostic: admin-only. Attempts a raw Gmail SMTP send and returns the
// actual error text so we can debug delivery failures without Railway shell.
// Usage: GET /admin/email-diag?to=friend@gmail.com  (needs x-admin-secret)
app.get('/admin/email-diag', adminAuth, async (req, res) => {
  try {
    const nodemailer = await import('nodemailer')
    const to = String(req.query.to || '')
    if (!to) return res.status(400).json({ error: 'pass ?to=someone@gmail.com' })

    const stripEnv = (v: string | undefined) =>
      (v ?? '').trim().replace(/^["']|["']$/g, '').trim()

    const gmailUser = stripEnv(process.env.GMAIL_USER)
    const gmailPass = stripEnv(process.env.GMAIL_APP_PASSWORD).replace(/\s+/g, '')
    const from = stripEnv(process.env.EMAIL_FROM) || `NeedHub <${gmailUser}>`

    const outcome: any = { attempted: true, from, to }
    const start = Date.now()

    if (!gmailUser || !gmailPass) {
      return res.json({
        outcome: { ok: false, error: 'GMAIL_USER or GMAIL_APP_PASSWORD not set' },
        envSnapshot: envSnapshot(process.env),
      })
    }

    try {
      const transporter = nodemailer.createTransport({
        host: 'smtp.gmail.com',
        port: 587,
        secure: false,
        auth: { user: gmailUser, pass: gmailPass },
      })
      // Verify connection first — this catches auth errors cleanly
      await transporter.verify()
      const info = await transporter.sendMail({
        from,
        to,
        subject: 'NeedHub email diagnostic',
        text: 'If you got this, Gmail SMTP is working. This was triggered from /admin/email-diag.',
      })
      Object.assign(outcome, {
        ok: true,
        elapsed: Date.now() - start,
        messageId: info.messageId,
        accepted: info.accepted,
        rejected: info.rejected,
        response: info.response,
      })
    } catch (err: any) {
      Object.assign(outcome, {
        ok: false,
        elapsed: Date.now() - start,
        error: err?.message ?? String(err),
        code: err?.code,
        responseCode: err?.responseCode,
        command: err?.command,
      })
    }
    res.json({ outcome, envSnapshot: envSnapshot(process.env) })
  } catch (err: any) {
    res.status(500).json({ error: err?.message ?? 'unknown' })
  }
})

function envSnapshot(env: NodeJS.ProcessEnv) {
  const u = env.GMAIL_USER ?? null
  const p = env.GMAIL_APP_PASSWORD ?? null
  return {
    GMAIL_USER_len: u?.length ?? 0,
    GMAIL_USER_hasQuotes: /^["']|["']$/.test(u ?? ''),
    GMAIL_USER_preview: u ? `${u.slice(0, 3)}***${u.slice(-8)}` : null,
    GMAIL_APP_PASSWORD_len: p?.length ?? 0,
    GMAIL_APP_PASSWORD_hasQuotes: /^["']|["']$/.test(p ?? ''),
    GMAIL_APP_PASSWORD_hasSpaces: /\s/.test(p ?? ''),
    EMAIL_FROM: env.EMAIL_FROM ?? null,
    RESEND_API_KEY_present: !!env.RESEND_API_KEY,
  }
}

app.use('/auth', authLimiter, authRouter)
// tighter limit on OTP resend specifically
app.use('/auth/resend-otp', otpLimiter)

// Needs router — self-contained authentication (per-route). Public GET, protected write.
app.use('/needs', writeLimiter, needsRouter)

// User-facing reports — every route requires auth.
app.use('/reports', writeLimiter, reportsRouter)

// Certificates — individual authenticate calls per route inside the router.
app.use('/certificates', uploadLimiter, certificatesRouter)

// Profiles — avatar upload + profile read/update.
app.use('/profile', profilesRouter)

// Messaging — DM threads + messages with optional image attachments.
// Uses a dedicated high-throughput limiter (300/min) because active
// conversations easily fire 5+ requests per exchange (send, mark-read,
// polling) and would blow through the standard writeLimiter.
app.use('/chats', messagingLimiter, messagingRouter)

// Friends + Blocks — requests, accept/decline, block/unblock.
app.use('/friends', friendsRouter)

// ChitChat — availability toggle + roster.
app.use('/chitchat', chitchatRouter)

// Notifications — inbox, unread count, read.
app.use('/notifications', notificationsRouter)

// Reviews — submit + pending + public reviews for a user.
app.use('/reviews', reviewsRouter)

// Redemptions — catalog + redeem + history.
app.use('/redemptions', redemptionsRouter)

// Achievements — user-submitted achievement claims.
app.use('/achievements', achievementsRouter)

// Protected sub-app. Feature routers that need blanket authenticate mount into this.
export const protectedRouter: ExpressRouter = Router()
protectedRouter.use(authenticate)
app.use('/protected', protectedRouter)

app.use('/admin', adminAuth, adminRouter)

// Global error handler — MUST be registered last, after every route.
// Maps HttpError -> { status, error, code }; anything else -> 500.
app.use(errorHandler)
