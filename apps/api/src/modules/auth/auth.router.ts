import { Router, type IRouter } from 'express'
import { authenticate } from '../../middleware/authenticate'
import type { AuthedRequest } from '../../middleware/authenticate'
import { badRequest, notFound } from '../../lib/http-error'
import { signupBody, loginBody, verifyEmailBody, resendOtpBody } from './auth.schemas'
import * as authService from './auth.service'

export const authRouter: IRouter = Router()

authRouter.post('/signup', async (req, res, next) => {
  const parsed = signupBody.safeParse(req.body)
  if (!parsed.success) return next(badRequest('Invalid signup payload', 'INVALID_BODY'))
  try {
    const result = await authService.signup(parsed.data)
    res.status(201).json(result)
  } catch (err) { next(err) }
})

authRouter.post('/verify-email', async (req, res, next) => {
  const parsed = verifyEmailBody.safeParse(req.body)
  if (!parsed.success) return next(badRequest('Invalid verification payload', 'INVALID_BODY'))
  try {
    const result = await authService.verifyEmail(parsed.data)
    res.json(result)
  } catch (err) { next(err) }
})

authRouter.post('/resend-otp', async (req, res, next) => {
  const parsed = resendOtpBody.safeParse(req.body)
  if (!parsed.success) return next(badRequest('Invalid resend payload', 'INVALID_BODY'))
  try {
    const result = await authService.resendOtp(parsed.data)
    res.json(result)
  } catch (err) { next(err) }
})

authRouter.post('/login', async (req, res, next) => {
  const parsed = loginBody.safeParse(req.body)
  if (!parsed.success) return next(badRequest('Invalid login payload', 'INVALID_BODY'))
  try {
    const result = await authService.login(parsed.data)
    res.json(result)
  } catch (err) { next(err) }
})

authRouter.get('/me', authenticate, async (req, res, next) => {
  try {
    const user = await authService.getMe((req as AuthedRequest).userId)
    res.json(user)
  } catch { next(notFound('User not found', 'USER_NOT_FOUND')) }
})
