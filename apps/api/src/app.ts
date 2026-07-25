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
import { authLimiter, otpLimiter, writeLimiter, uploadLimiter } from './middleware/rateLimiter'
import { config } from './config'

export const app: Express = express()
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
app.use('/chats', writeLimiter, messagingRouter)

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
