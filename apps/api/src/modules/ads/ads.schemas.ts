import { z } from 'zod'

export const createAdInquiryBody = z.object({
  name: z.string().min(1, 'Name is required').max(100),
  email: z.string().email().optional().nullable(),
  phone: z.string().min(5).max(20).optional().nullable(),
  product: z.string().min(1, 'Product/service description is required').max(500),
  message: z.string().max(1000).optional().nullable(),
}).refine(
  (data) => data.email || data.phone,
  { message: 'Either email or phone is required', path: ['email'] }
)
