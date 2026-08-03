// plus-rewards.ts imports lib/prisma at module load time (for
// fetchVerifiedPoints, unused by these pure-function tests), which needs
// DATABASE_URL present for the import itself to succeed — same convention
// as needs/__tests__/scoreNeed.test.ts.
import 'dotenv/config'
import { describe, it, expect } from 'vitest'
import {
  evaluateRewardEligibility, fingerprintPayoutDetails, validatePayoutDetails, type RewardEligibilityInput,
} from '../plus-rewards'

function baseInput(overrides: Partial<RewardEligibilityInput> = {}): RewardEligibilityInput {
  return {
    offer: {
      enabled: true,
      startsAt: null,
      endsAt: null,
      maxRedemptions: -1,
      redeemedCount: 0,
      minVerifiedPoints: 1000,
      pointsCost: 1000,
      minVerificationLevel: null,
      minAccountAgeDays: 0,
    },
    alreadyClaimed: false,
    verifiedPoints: 1500,
    spendableBalance: 1500,
    verificationLevel: 'EMAIL',
    accountAgeDays: 30,
    now: new Date('2026-06-15T00:00:00Z'),
    ...overrides,
  }
}

describe('evaluateRewardEligibility', () => {
  it('is eligible when every gate passes', () => {
    expect(evaluateRewardEligibility(baseInput())).toEqual({ eligible: true })
  })

  it('rejects when the offer is disabled', () => {
    const input = baseInput({ offer: { ...baseInput().offer, enabled: false } })
    expect(evaluateRewardEligibility(input)).toEqual({ eligible: false, reason: 'OFFER_DISABLED' })
  })

  it('rejects before the offer window has started', () => {
    const input = baseInput({ offer: { ...baseInput().offer, startsAt: new Date('2027-01-01') } })
    expect(evaluateRewardEligibility(input)).toEqual({ eligible: false, reason: 'OFFER_NOT_STARTED' })
  })

  it('rejects after the offer window has ended', () => {
    const input = baseInput({ offer: { ...baseInput().offer, endsAt: new Date('2026-01-01') } })
    expect(evaluateRewardEligibility(input)).toEqual({ eligible: false, reason: 'OFFER_ENDED' })
  })

  it('rejects once maxRedemptions is reached', () => {
    const input = baseInput({ offer: { ...baseInput().offer, maxRedemptions: 100, redeemedCount: 100 } })
    expect(evaluateRewardEligibility(input)).toEqual({ eligible: false, reason: 'OFFER_EXHAUSTED' })
  })

  it('unlimited maxRedemptions (-1) is never exhausted regardless of redeemedCount', () => {
    const input = baseInput({ offer: { ...baseInput().offer, maxRedemptions: -1, redeemedCount: 999_999 } })
    expect(evaluateRewardEligibility(input)).toEqual({ eligible: true })
  })

  it('rejects a user who already claimed this offer', () => {
    expect(evaluateRewardEligibility(baseInput({ alreadyClaimed: true })))
      .toEqual({ eligible: false, reason: 'ALREADY_CLAIMED' })
  })

  it('rejects below the verified-points threshold, even with a high spendable balance', () => {
    const input = baseInput({ verifiedPoints: 999, spendableBalance: 5000 })
    expect(evaluateRewardEligibility(input)).toEqual({ eligible: false, reason: 'BELOW_VERIFIED_POINTS' })
  })

  it('rejects insufficient spendable balance, even with plenty of verified points — these are different numbers', () => {
    const input = baseInput({ verifiedPoints: 10000, spendableBalance: 500 })
    expect(evaluateRewardEligibility(input)).toEqual({ eligible: false, reason: 'INSUFFICIENT_BALANCE' })
  })

  it('a heavy contributor who spent points on boosts (low pointsTotal, high verified) is correctly gated on balance, not blocked on verified points', () => {
    // This is exactly the trap the plan calls out: using pointsTotal for the
    // verified-points threshold would wrongly disqualify this user.
    const input = baseInput({ verifiedPoints: 50000, spendableBalance: 200 })
    expect(evaluateRewardEligibility(input)).toEqual({ eligible: false, reason: 'INSUFFICIENT_BALANCE' })
  })

  it('rejects below the required verification level', () => {
    const input = baseInput({
      offer: { ...baseInput().offer, minVerificationLevel: 'PHONE' },
      verificationLevel: 'EMAIL',
    })
    expect(evaluateRewardEligibility(input)).toEqual({ eligible: false, reason: 'VERIFICATION_LEVEL_TOO_LOW' })
  })

  it('accepts a verification level above the required one', () => {
    const input = baseInput({
      offer: { ...baseInput().offer, minVerificationLevel: 'PHONE' },
      verificationLevel: 'ID',
    })
    expect(evaluateRewardEligibility(input)).toEqual({ eligible: true })
  })

  it('rejects an account younger than minAccountAgeDays', () => {
    const input = baseInput({ offer: { ...baseInput().offer, minAccountAgeDays: 90 }, accountAgeDays: 10 })
    expect(evaluateRewardEligibility(input)).toEqual({ eligible: false, reason: 'ACCOUNT_TOO_NEW' })
  })
})

describe('fingerprintPayoutDetails', () => {
  it('produces the same fingerprint for the same UPI id regardless of case/whitespace', () => {
    const a = fingerprintPayoutDetails({ upiId: '  Someone@UPI ' })
    const b = fingerprintPayoutDetails({ upiId: 'someone@upi' })
    expect(a).toBe(b)
  })

  it('produces different fingerprints for different payout ids', () => {
    const a = fingerprintPayoutDetails({ upiId: 'alice@upi' })
    const b = fingerprintPayoutDetails({ upiId: 'bob@upi' })
    expect(a).not.toBe(b)
  })

  it('never throws on missing/empty payout details', () => {
    expect(() => fingerprintPayoutDetails({})).not.toThrow()
  })
})

describe('validatePayoutDetails', () => {
  const upiField = [{ key: 'upiId', label: 'UPI ID', type: 'upi' as const, required: true }]

  it('accepts a well-formed UPI id', () => {
    expect(validatePayoutDetails(upiField, { upiId: 'someone@upi' })).toEqual({ valid: true })
  })

  it('rejects a missing required field', () => {
    const result = validatePayoutDetails(upiField, {})
    expect(result.valid).toBe(false)
  })

  it('rejects a malformed UPI id', () => {
    const result = validatePayoutDetails(upiField, { upiId: 'not-a-upi-id' })
    expect(result.valid).toBe(false)
  })

  it('an optional field can be omitted without failing validation', () => {
    const optional = [{ key: 'note', label: 'Note', type: 'text' as const, required: false }]
    expect(validatePayoutDetails(optional, {})).toEqual({ valid: true })
  })
})
