import { z } from 'zod'

const needType = z.enum(['EARN', 'CONNECT'])
const earnCategory = z.enum(['TUTORING', 'FREELANCE', 'GOODS_BUY', 'GOODS_SELL', 'REPAIR', 'OTHER'])
const connectCategory = z.enum(['STUDY_PARTNER', 'ACTIVITY_PARTNER', 'HOBBY', 'MENTOR', 'OTHER'])
const status = z.enum(['OPEN', 'IN_PROGRESS', 'FULFILLED', 'CLOSED'])

export const decomposeBody = z.object({
  text: z.string().min(3).max(3000),
})

const decomposedNeed = z.object({
  title: z.string().min(1).max(120),
  description: z.string().min(1).max(2000),
  needType,
  earnCategory: earnCategory.nullable(),
  connectCategory: connectCategory.nullable(),
  budgetMin: z.number().nullable(),
  budgetMax: z.number().nullable(),
  deadline: z.string().nullable(),
  locationText: z.string().max(200).nullable().optional(),
  lat: z.number().nullable().optional(),
  lng: z.number().nullable().optional(),
})

export const createNeedBody = z.object({
  needs: z.array(decomposedNeed).min(1).max(6),
})

export const feedQuery = z.object({
  type: needType.optional(),
  distanceKm: z.coerce.number().min(0).max(1000).optional(),
  minBudget: z.coerce.number().min(0).optional(),
  maxBudget: z.coerce.number().min(0).optional(),
  interests: z
    .union([z.string(), z.array(z.string())])
    .transform((v) => (Array.isArray(v) ? v : v.split(',')))
    .optional(),
  genders: z
    .union([z.string(), z.array(z.string())])
    .transform((v) => (Array.isArray(v) ? v : v.split(',')))
    .optional(),
  lat: z.coerce.number().optional(),
  lng: z.coerce.number().optional(),
  take: z.coerce.number().min(1).max(100).default(30),
  skip: z.coerce.number().min(0).default(0),
})

export const respondBody = z.object({
  message: z.string().min(1).max(2000),
  quotedPrice: z.coerce.number().min(0).nullable().optional(),
})

export const respondDecisionBody = z.object({
  status: z.enum(['ACCEPTED', 'DECLINED']),
})

export const statusBody = z.object({
  status,
})

export type DecomposeBody = z.infer<typeof decomposeBody>
export type CreateNeedBody = z.infer<typeof createNeedBody>
export type FeedQuery = z.infer<typeof feedQuery>
export type RespondBody = z.infer<typeof respondBody>
export type RespondDecisionBody = z.infer<typeof respondDecisionBody>
export type StatusBody = z.infer<typeof statusBody>
