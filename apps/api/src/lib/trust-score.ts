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

/**
 * Weights sum to exactly 100, so a perfect score is reachable and every point
 * is accounted for. Ordered by how much each signal actually tells you about
 * whether this person is safe to meet:
 *
 *   phone 25    out-of-band OTP on a real, reachable number — hardest to fake
 *   face  20    live selfie check
 *   reviews 15  what people who actually dealt with them say
 *   fulfilled 15  real completed outcomes
 *   badges 10   earned milestones (see badges.ts)
 *   certificates 10  admin-reviewed credentials — weaker than real outcomes
 *   email 5     compulsory and trivial to obtain, so it counts least
 *
 * The badge slice was taken from email (10 -> 5) and certificates (15 -> 10)
 * specifically because those are the two weakest signals. Phone, face, reviews
 * and fulfilled needs are untouched, so existing scores stay stable — most
 * users recover the 5 email points through badges they already qualify for.
 */
export const TRUST_WEIGHTS = {
  email: 5,
  face: 20,
  phone: 25,
  certificateEach: 5,
  certificateCap: 10,
  fulfilledEach: 2,
  fulfilledCap: 15,
  reviewsMax: 15,
  badgeEach: 1,
  badgeCap: 10,
} as const

export interface TrustInputs {
  emailVerifiedAt: Date | null
  phoneVerifiedAt: Date | null
  faceVerifiedAt: Date | null
  approvedCertificateCount: number
  /**
   * Completed needs, counting needs this user *helped with* as well as needs
   * they posted that reached FULFILLED. Helping someone else is the stronger
   * signal, but following through on your own asks counts too.
   */
  fulfilledNeedCount: number
  avgRating: number // 0 when ratingCount is 0
  ratingCount: number
  /** Earned badges — see `earnedBadgeCount` in badges.ts. */
  earnedBadgeCount: number
}

export function computeTrustScore(input: TrustInputs): number {
  let score = 0
  if (input.emailVerifiedAt) score += TRUST_WEIGHTS.email
  if (input.faceVerifiedAt) score += TRUST_WEIGHTS.face
  if (input.phoneVerifiedAt) score += TRUST_WEIGHTS.phone
  score += Math.min(input.approvedCertificateCount * TRUST_WEIGHTS.certificateEach, TRUST_WEIGHTS.certificateCap)
  score += Math.min(input.fulfilledNeedCount * TRUST_WEIGHTS.fulfilledEach, TRUST_WEIGHTS.fulfilledCap)
  if (input.ratingCount > 0) score += Math.round((input.avgRating / 5) * TRUST_WEIGHTS.reviewsMax)
  score += Math.min(input.earnedBadgeCount * TRUST_WEIGHTS.badgeEach, TRUST_WEIGHTS.badgeCap)
  return Math.min(100, score)
}
