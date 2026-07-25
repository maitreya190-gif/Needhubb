import { z } from 'zod'

export const signupBody = z.object({
  email: z.string().email(),
  password: z.string().min(8, 'Password must be at least 8 characters'),
  displayName: z.string().min(2).max(50),
})

export const loginBody = z.object({
  email: z.string().email(),
  password: z.string().min(1),
})

export const verifyEmailBody = z.object({
  userId: z.string().min(1),
  code: z.string().regex(/^\d{6}$/, 'Code must be exactly 6 digits'),
})

export const resendOtpBody = z.object({
  userId: z.string().min(1),
})

export type SignupBody = z.infer<typeof signupBody>
export type LoginBody = z.infer<typeof loginBody>
export type VerifyEmailBody = z.infer<typeof verifyEmailBody>
export type ResendOtpBody = z.infer<typeof resendOtpBody>
