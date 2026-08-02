import { z } from 'zod'

export const createVouchBody = z.object({
  voucheeId: z.string().min(1),
  skillId: z.string().min(1),
  testimonial: z.string().max(500).optional(),
})

export const editVouchBody = z.object({
  testimonial: z.string().max(500).nullable(),
})

export type CreateVouchBody = z.infer<typeof createVouchBody>
export type EditVouchBody = z.infer<typeof editVouchBody>
