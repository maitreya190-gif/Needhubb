import rateLimit from 'express-rate-limit'
import type { Request, Response, NextFunction } from 'express'

const make = (windowMs: number, max: number) =>
  rateLimit({
    windowMs,
    max,
    standardHeaders: true,
    legacyHeaders: false,
    message: { error: 'Too many requests, please try again later.', code: 'RATE_LIMITED' },
  })

// Auth routes — tight to blunt brute force and OTP spam.
export const authLimiter = make(15 * 60 * 1000, 20)       // 20 req / 15 min
export const otpLimiter  = make(60 * 1000, 3)              // 3 req / min

// Write routes — loose enough for normal use, blocks scripts.
export const writeLimiter = make(60 * 1000, 30)            // 30 req / min
export const uploadLimiter = make(60 * 1000, 10)           // 10 uploads / min

// Fallback no-op kept for routes that don't need limiting.
export function rateLimiter(_req: Request, _res: Response, next: NextFunction) {
  next()
}
