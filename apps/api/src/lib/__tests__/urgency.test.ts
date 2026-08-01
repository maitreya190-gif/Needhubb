/**
 * Urgency Mode is additive and internal-only, so the two properties that
 * matter most are: (1) a non-urgent need is completely untouched — every pure
 * function here must return a no-op for isUrgent=false, and (2) nothing
 * internal ever reaches a plain object the way a client response would see
 * it. Both are pinned directly below.
 *
 * Scope note: `evaluateAndStoreUrgency`'s full orchestration (trust score +
 * track record + badges + the LLM call) is not re-mocked here — it was
 * verified directly against live production data during development (see the
 * PR description) and re-mocking four modules' worth of dependencies to test
 * my own mocks would add ceremony without real coverage. What's covered here
 * is everything DB-touching that's self-contained enough to verify honestly:
 * fail-safe behaviour, and that a UrgencyProfile write actually shapes the
 * query the way the reliability rules require.
 */

import { describe, it, expect, vi, beforeEach } from 'vitest'

const mocks = vi.hoisted(() => ({
  needCount: vi.fn(),
  interestResponseCount: vi.fn(),
  urgencyProfileFindUnique: vi.fn(),
  urgencyProfileUpsert: vi.fn(),
  needUpdateMany: vi.fn(),
}))

vi.mock('../prisma', () => ({
  prisma: {
    need: { count: mocks.needCount, updateMany: mocks.needUpdateMany },
    interestResponse: { count: mocks.interestResponseCount },
    urgencyProfile: { findUnique: mocks.urgencyProfileFindUnique, upsert: mocks.urgencyProfileUpsert },
  },
}))

import {
  computeUrgencyBoost, computeRescueStage, rescueDistanceMultiplier, rescueScoreBonus,
  isExpired, expireIfNeeded, marketPressure, getReliability, recordUrgentNeedCreated,
  recordUrgentNeedFulfilled, stripInternalUrgencyFields,
  URGENCY_MAX_BOOST, RESCUE_MIN_CONFIDENCE,
} from '../urgency'

function h(hours: number): Date {
  return new Date(Date.now() + hours * 3_600_000)
}

beforeEach(() => {
  Object.values(mocks).forEach((m) => m.mockReset())
})

describe('a non-urgent need is untouched — the core additive guarantee', () => {
  const notUrgent = { isUrgent: false, urgencyConfidence: 0.9, deadline: h(1), status: 'OPEN' }

  it('contributes zero to the score', () => {
    expect(computeUrgencyBoost(notUrgent)).toBe(0)
  })

  it('never enters Rescue Mode', () => {
    expect(computeRescueStage(notUrgent, 0)).toBe(0)
  })

  it('is never treated as expired, however old the deadline', () => {
    expect(isExpired({ ...notUrgent, deadline: h(-1000) })).toBe(false)
  })
})

describe('computeUrgencyBoost', () => {
  it('is zero with no confidence yet (the window right after creation)', () => {
    expect(computeUrgencyBoost({ isUrgent: true, urgencyConfidence: null, deadline: h(1), status: 'OPEN' })).toBe(0)
  })

  it('is zero once the deadline has passed', () => {
    expect(computeUrgencyBoost({ isUrgent: true, urgencyConfidence: 0.9, deadline: h(-1), status: 'OPEN' })).toBe(0)
  })

  it('is zero for a need with no deadline at all', () => {
    expect(computeUrgencyBoost({ isUrgent: true, urgencyConfidence: 0.9, deadline: null, status: 'OPEN' })).toBe(0)
  })

  it('never exceeds the cap, even at maximum confidence and an imminent deadline', () => {
    const boost = computeUrgencyBoost({ isUrgent: true, urgencyConfidence: 1, deadline: h(0.01), status: 'OPEN' })
    expect(boost).toBeLessThanOrEqual(URGENCY_MAX_BOOST)
  })

  it('grows as the deadline approaches, for the same confidence', () => {
    const far = computeUrgencyBoost({ isUrgent: true, urgencyConfidence: 0.8, deadline: h(60), status: 'OPEN' })
    const near = computeUrgencyBoost({ isUrgent: true, urgencyConfidence: 0.8, deadline: h(2), status: 'OPEN' })
    expect(near).toBeGreaterThan(far)
  })

  it('scales with confidence — a moderate claim gets a proportional nudge, not a flat one', () => {
    const low = computeUrgencyBoost({ isUrgent: true, urgencyConfidence: 0.2, deadline: h(2), status: 'OPEN' })
    const high = computeUrgencyBoost({ isUrgent: true, urgencyConfidence: 0.9, deadline: h(2), status: 'OPEN' })
    expect(high).toBeGreaterThan(low)
    expect(low).toBeGreaterThan(0) // still a nonzero nudge, not a reject
  })

  // The explicit ask: fulfilling a need turns urgency off.
  for (const status of ['FULFILLED', 'CLOSED', 'EXPIRED']) {
    it(`is zero once status is ${status}`, () => {
      expect(computeUrgencyBoost({ isUrgent: true, urgencyConfidence: 0.95, deadline: h(1), status })).toBe(0)
    })
  }
})

describe('computeRescueStage', () => {
  const base = { isUrgent: true, urgencyConfidence: 0.6, status: 'OPEN' }

  it('stays at 0 while the deadline is more than a day out', () => {
    expect(computeRescueStage({ ...base, deadline: h(30) }, 0)).toBe(0)
  })

  it('progresses through stages 1, 2, 3 as the deadline closes in with zero engagement', () => {
    expect(computeRescueStage({ ...base, deadline: h(20) }, 0)).toBe(1)
    expect(computeRescueStage({ ...base, deadline: h(10) }, 0)).toBe(2)
    expect(computeRescueStage({ ...base, deadline: h(3) }, 0)).toBe(3)
  })

  it('a single response stands the need down from rescue entirely', () => {
    expect(computeRescueStage({ ...base, deadline: h(3) }, 1)).toBe(0)
  })

  it('is gated by confidence — a weak claim never gets rescued', () => {
    const weak = { ...base, urgencyConfidence: RESCUE_MIN_CONFIDENCE - 0.01, deadline: h(3) }
    expect(computeRescueStage(weak, 0)).toBe(0)
  })

  it('a confidence right at the floor still qualifies', () => {
    const atFloor = { ...base, urgencyConfidence: RESCUE_MIN_CONFIDENCE, deadline: h(3) }
    expect(computeRescueStage(atFloor, 0)).toBe(3)
  })

  it('never triggers once the need is fulfilled', () => {
    expect(computeRescueStage({ ...base, status: 'FULFILLED', deadline: h(3) }, 0)).toBe(0)
  })

  it('never triggers past the deadline — that is expiry, not rescue', () => {
    expect(computeRescueStage({ ...base, deadline: h(-1) }, 0)).toBe(0)
  })
})

describe('rescue mechanisms stay bounded', () => {
  it('distance multiplier is 1 (no change) below stage 2', () => {
    expect(rescueDistanceMultiplier(0)).toBe(1)
    expect(rescueDistanceMultiplier(1)).toBe(1)
  })

  it('distance multiplier expands, but by a fixed, capped amount', () => {
    expect(rescueDistanceMultiplier(2)).toBeGreaterThan(1)
    expect(rescueDistanceMultiplier(3)).toBeGreaterThan(rescueDistanceMultiplier(2))
    expect(rescueDistanceMultiplier(3)).toBeLessThanOrEqual(3) // sane upper bound
  })

  it('the score bonus only applies at stage 3, and is small', () => {
    expect(rescueScoreBonus(0)).toBe(0)
    expect(rescueScoreBonus(1)).toBe(0)
    expect(rescueScoreBonus(2)).toBe(0)
    expect(rescueScoreBonus(3)).toBeGreaterThan(0)
    expect(rescueScoreBonus(3)).toBeLessThan(0.1)
  })
})

describe('isExpired', () => {
  it('true for an urgent need past its deadline and still open', () => {
    expect(isExpired({ isUrgent: true, deadline: h(-1), status: 'OPEN' })).toBe(true)
  })

  it('false before the deadline', () => {
    expect(isExpired({ isUrgent: true, deadline: h(1), status: 'OPEN' })).toBe(false)
  })

  it('false once fulfilled, however late — done is done, not abandoned', () => {
    expect(isExpired({ isUrgent: true, deadline: h(-100), status: 'FULFILLED' })).toBe(false)
  })

  it('false with no deadline set', () => {
    expect(isExpired({ isUrgent: true, deadline: null, status: 'OPEN' })).toBe(false)
  })
})

describe('stripInternalUrgencyFields', () => {
  it('removes urgencyConfidence and keeps everything else, including isUrgent', () => {
    const need = { id: 'n1', isUrgent: true, urgencyConfidence: 0.77, title: 'Help' }
    const stripped = stripInternalUrgencyFields(need)
    expect(stripped).toEqual({ id: 'n1', isUrgent: true, title: 'Help' })
    expect('urgencyConfidence' in stripped).toBe(false)
  })

  it('is a no-op shape-wise on an object that never had the field', () => {
    const need = { id: 'n2', title: 'Also help', urgencyConfidence: undefined }
    expect(stripInternalUrgencyFields(need)).toEqual({ id: 'n2', title: 'Also help' })
  })
})

describe('degrades safely when the database is unavailable', () => {
  it('marketPressure returns neutral 0.5 rather than throwing', async () => {
    mocks.needCount.mockRejectedValue(new Error('DB down'))
    await expect(marketPressure('EARN', 'TUTORING', null)).resolves.toBe(0.5)
  })

  it('getReliability returns the neutral default rather than throwing', async () => {
    mocks.urgencyProfileFindUnique.mockRejectedValue(new Error('DB down'))
    await expect(getReliability('user-1')).resolves.toBe(0.5)
  })

  it('recordUrgentNeedCreated resolves rather than throwing', async () => {
    mocks.urgencyProfileUpsert.mockRejectedValue(new Error('DB down'))
    await expect(recordUrgentNeedCreated('user-1')).resolves.toBeUndefined()
  })

  it('recordUrgentNeedFulfilled resolves rather than throwing', async () => {
    mocks.urgencyProfileFindUnique.mockRejectedValue(new Error('DB down'))
    await expect(recordUrgentNeedFulfilled('user-1')).resolves.toBeUndefined()
  })

  it('expireIfNeeded resolves rather than throwing when the write fails', async () => {
    mocks.needUpdateMany.mockRejectedValue(new Error('DB down'))
    await expect(expireIfNeeded({
      id: 'n1', posterId: 'user-1', isUrgent: true, deadline: h(-1), status: 'OPEN', responseCount: 0,
    })).resolves.toBeUndefined()
  })

  it('expireIfNeeded is a no-op for a need that is not actually expired', async () => {
    await expireIfNeeded({
      id: 'n1', posterId: 'user-1', isUrgent: true, deadline: h(1), status: 'OPEN', responseCount: 0,
    })
    expect(mocks.needUpdateMany).not.toHaveBeenCalled()
  })
})

describe('reliability nudges are applied exactly once', () => {
  it('a brand-new profile ends up at neutral + one nudge, not neutral + two', async () => {
    mocks.urgencyProfileFindUnique.mockResolvedValue(null)
    mocks.urgencyProfileUpsert.mockResolvedValue({})
    await recordUrgentNeedFulfilled('user-1')
    const createArg = mocks.urgencyProfileUpsert.mock.calls[0][0].create
    // 0.5 neutral + a single up-nudge, not 0.5 + nudge + nudge.
    expect(createArg.reliability).toBeGreaterThan(0.5)
    expect(createArg.reliability).toBeLessThan(0.65)
  })

  it('an existing profile is nudged from its current value, not reset to neutral', async () => {
    mocks.urgencyProfileFindUnique.mockResolvedValue({ reliability: 0.9, justifiedCount: 2, misusedCount: 0 })
    mocks.urgencyProfileUpsert.mockResolvedValue({})
    await recordUrgentNeedFulfilled('user-1')
    const updateArg = mocks.urgencyProfileUpsert.mock.calls[0][0].update
    expect(updateArg.reliability).toBeGreaterThan(0.9) // nudged up further
    expect(updateArg.reliability).toBeLessThanOrEqual(1) // still clamped
  })
})
