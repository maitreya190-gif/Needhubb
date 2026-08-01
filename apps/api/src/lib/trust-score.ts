/**
 * Trust score — a 0-100 number built from identity verification AND actual
 * on-platform track record. Shown on profiles and Connect cards so people
 * meeting strangers in person have a real, at-a-glance safety signal.
 *
 * Deliberately NOT the same thing as Impact points — see PointsLedger. Trust
 * score has its own weights and is never spendable; it only moves when a
 * verification happens or a real outcome (fulfilled need, review, approved
 * certificate) lands.
 *
 * Verification weights are intentionally uneven: email is compulsory and
 * trivial to obtain (effectively free), so it counts least. Face verification
 * requires a live selfie check. Phone requires owning a real, reachable
 * number and out-of-band OTP proof, so it counts most.
 */

export const TRUST_WEIGHTS = {
  email: 10,
  face: 20,
  phone: 25,
  certificateEach: 5,
  certificateCap: 15,
  fulfilledEach: 2,
  fulfilledCap: 15,
  reviewsMax: 15,
} as const

export interface TrustInputs {
  emailVerifiedAt: Date | null
  phoneVerifiedAt: Date | null
  faceVerifiedAt: Date | null
  approvedCertificateCount: number
  fulfilledNeedCount: number
  avgRating: number // 0 when ratingCount is 0
  ratingCount: number
}

export function computeTrustScore(input: TrustInputs): number {
  let score = 0
  if (input.emailVerifiedAt) score += TRUST_WEIGHTS.email
  if (input.faceVerifiedAt) score += TRUST_WEIGHTS.face
  if (input.phoneVerifiedAt) score += TRUST_WEIGHTS.phone
  score += Math.min(input.approvedCertificateCount * TRUST_WEIGHTS.certificateEach, TRUST_WEIGHTS.certificateCap)
  score += Math.min(input.fulfilledNeedCount * TRUST_WEIGHTS.fulfilledEach, TRUST_WEIGHTS.fulfilledCap)
  if (input.ratingCount > 0) score += Math.round((input.avgRating / 5) * TRUST_WEIGHTS.reviewsMax)
  return Math.min(100, score)
}
