import { Router, type IRouter } from 'express'
import { prisma } from '../../lib/prisma'
import { badRequest } from '../../lib/http-error'
import { createAdInquiryBody } from './ads.schemas'

export const adsRouter: IRouter = Router()

adsRouter.post('/', async (req, res, next) => {
  const parsed = createAdInquiryBody.safeParse(req.body)
  if (!parsed.success) return next(badRequest(parsed.error.errors[0]?.message ?? 'Invalid payload', 'INVALID_BODY'))
  try {
    const inquiry = await prisma.adInquiry.create({ data: parsed.data })
    res.status(201).json(inquiry)
  } catch (err) { next(err) }
})
