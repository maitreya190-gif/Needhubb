/**
 * Reward-catalog eligibility and payout-detail helpers for the admin-
 * configurable reward system (RewardOffer/RewardClaim). The launch ₹150
 * cashback is just the first row in this catalog — see RewardOffer.kind and
 * payoutFieldsJson for how a voucher or gift-card reward slots in later
 * without any code change.
 *
 * "Verified Impact Points" (SUM of positive PointsLedger deltas — the same
 * definition lib/impact-league.ts already uses for season standing) and
 * Profile.pointsTotal (the spendable balance, net of everything already
 * spent) are DIFFERENT numbers. The eligibility threshold checks the
 * former; the spend cost checks the latter. Using either alone is wrong —
 * see evaluateRewardEligibility below.
 */

import crypto from 'node:crypto'
import { prisma } from './prisma'

export type RewardIneligibleReason =
  | 'OFFER_DISABLED'
  | 'OFFER_NOT_STARTED'
  | 'OFFER_ENDED'
  | 'OFFER_EXHAUSTED'
  | 'ALREADY_CLAIMED'
  | 'BELOW_VERIFIED_POINTS'
  | 'INSUFFICIENT_BALANCE'
  | 'VERIFICATION_LEVEL_TOO_LOW'
  | 'ACCOUNT_TOO_NEW'

export type RewardEligibility =
  | { eligible: true }
  | { eligible: false; reason: RewardIneligibleReason }

const VERIFICATION_RANK: Record<string, number> = { EMAIL: 0, PHONE: 1, ID: 2 }

export interface RewardEligibilityInput {
  offer: {
    enabled: boolean
    startsAt: Date | null
    endsAt: Date | null
    maxRedemptions: number
    redeemedCount: number
    minVerifiedPoints: number
    pointsCost: number
    minVerificationLevel: string | null
    minAccountAgeDays: number
  }
  alreadyClaimed: boolean
  verifiedPoints: number
  spendableBalance: number
  verificationLevel: string
  accountAgeDays: number
  now?: Date
}

/** Pure eligibility decision — no I/O, fully unit-testable. */
export function evaluateRewardEligibility(input: RewardEligibilityInput): RewardEligibility {
  const now = input.now ?? new Date()
  const { offer } = input

  if (!offer.enabled) return { eligible: false, reason: 'OFFER_DISABLED' }
  if (offer.startsAt && offer.startsAt.getTime() > now.getTime()) return { eligible: false, reason: 'OFFER_NOT_STARTED' }
  if (offer.endsAt && offer.endsAt.getTime() < now.getTime()) return { eligible: false, reason: 'OFFER_ENDED' }
  if (offer.maxRedemptions !== -1 && offer.redeemedCount >= offer.maxRedemptions) {
    return { eligible: false, reason: 'OFFER_EXHAUSTED' }
  }
  if (input.alreadyClaimed) return { eligible: false, reason: 'ALREADY_CLAIMED' }
  if (input.verifiedPoints < offer.minVerifiedPoints) return { eligible: false, reason: 'BELOW_VERIFIED_POINTS' }
  if (input.spendableBalance < offer.pointsCost) return { eligible: false, reason: 'INSUFFICIENT_BALANCE' }
  if (offer.minVerificationLevel) {
    const required = VERIFICATION_RANK[offer.minVerificationLevel] ?? 0
    const actual = VERIFICATION_RANK[input.verificationLevel] ?? 0
    if (actual < required) return { eligible: false, reason: 'VERIFICATION_LEVEL_TOO_LOW' }
  }
  if (input.accountAgeDays < offer.minAccountAgeDays) return { eligible: false, reason: 'ACCOUNT_TOO_NEW' }

  return { eligible: true }
}

/** A user's all-time verified Impact Points — SUM of positive ledger deltas. */
export async function fetchVerifiedPoints(userId: string): Promise<number> {
  try {
    const agg = await prisma.pointsLedger.aggregate({
      where: { userId, delta: { gt: 0 } },
      _sum: { delta: true },
    })
    return agg._sum.delta ?? 0
  } catch (err) {
    console.error('[plus-rewards] failed to fetch verified points', userId, err)
    return 0
  }
}

/**
 * Normalizes and hashes a payout identifier (e.g. a UPI id) so admins can
 * spot "N other claims use this payout id" without storing it in the clear
 * alongside every claim. Not used to auto-reject — families legitimately
 * share a UPI id — only to surface for human review.
 */
export function fingerprintPayoutDetails(payoutDetails: Record<string, unknown>): string {
  const primary = (payoutDetails.upiId ?? payoutDetails.email ?? payoutDetails.accountNumber ?? '') as string
  const normalized = String(primary).trim().toLowerCase()
  return crypto.createHash('sha256').update(normalized).digest('hex')
}

const UPI_REGEX = /^[\w.-]{2,256}@[a-zA-Z]{2,64}$/
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

export interface PayoutFieldSpec {
  key: string
  label: string
  type: 'upi' | 'email' | 'text'
  required: boolean
}

/** Validates submitted payout details against an offer's declared field spec. */
export function validatePayoutDetails(
  fields: PayoutFieldSpec[],
  details: Record<string, unknown>,
): { valid: true } | { valid: false; message: string } {
  for (const field of fields) {
    const value = details[field.key]
    const str = typeof value === 'string' ? value.trim() : ''
    if (field.required && !str) {
      return { valid: false, message: `${field.label} is required` }
    }
    if (str && field.type === 'upi' && !UPI_REGEX.test(str)) {
      return { valid: false, message: `${field.label} doesn't look like a valid UPI ID` }
    }
    if (str && field.type === 'email' && !EMAIL_REGEX.test(str)) {
      return { valid: false, message: `${field.label} doesn't look like a valid email` }
    }
  }
  return { valid: true }
}
