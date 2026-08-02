import { z } from 'zod'

const needType = z.enum(['EARN', 'CONNECT'])
const earnCategory = z.enum(['TUTORING', 'FREELANCE', 'GOODS_BUY', 'GOODS_SELL', 'REPAIR', 'OTHER'])
const connectCategory = z.enum(['STUDY_PARTNER', 'ACTIVITY_PARTNER', 'HOBBY', 'MENTOR', 'OTHER'])
const status = z.enum(['OPEN', 'IN_PROGRESS', 'FULFILLED', 'CLOSED'])
// EXPIRED is system-set only (see lib/urgency.ts) — kept out of `status` above
// so a user can never PATCH their own need into or out of it, but included
// here so a client can still filter feedQuery for their own expired needs.
const queryableStatus = z.enum([...status.options, 'EXPIRED'])

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
  peopleNeeded: z.number().int().min(1).max(100).default(1),
  // Urgency Mode — optional, off unless the poster explicitly opts in on this
  // specific need. Everything downstream of this flag is additive; omitting
  // it (every existing caller) behaves exactly as before.
  isUrgent: z.boolean().optional(),
}).superRefine((val, ctx) => {
  if (val.isUrgent && !val.deadline) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['deadline'],
      message: 'A deadline is required when Urgency Mode is enabled',
    })
  }
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
  status: queryableStatus.optional(),
})

export const respondBody = z.object({
  message: z.string().min(1).max(2000),
  quotedPrice: z.coerce.number().min(0).nullable().optional(),
  removeWorkSample: z
    .union([z.boolean(), z.string()])
    .optional()
    .transform((v) => v === true || v === 'true' || v === '1'),
})

export const respondDecisionBody = z.object({
  status: z.enum(['ACCEPTED', 'DECLINED']),
})

export const editResponseBody = respondBody

export const statusBody = z.object({
  status,
})

// A renewed need is always urgent again by definition — the whole point is
// re-establishing a deadline after the old one passed — so this only asks
// for the new deadline itself, not an isUrgent flag.
export const renewNeedBody = z.object({
  deadline: z.string().min(1),
})

export type DecomposeBody = z.infer<typeof decomposeBody>
export type CreateNeedBody = z.infer<typeof createNeedBody>
export type FeedQuery = z.infer<typeof feedQuery>
export type RespondBody = z.infer<typeof respondBody>
export type RespondDecisionBody = z.infer<typeof respondDecisionBody>
export type EditResponseBody = z.infer<typeof editResponseBody>
export type StatusBody = z.infer<typeof statusBody>
