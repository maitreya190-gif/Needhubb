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
  recordUrgentNeedFulfilled, stripInternalUrgencyFields, urgencyRankContribution,
  renewalDampeningFactor, urgencyVisibilityCap, selectBoostedWithinCap,
  URGENCY_MAX_BOOST, RESCUE_MIN_CONFIDENCE,
  RENEWAL_DAMPENING_PER_GENERATION, RENEWAL_DAMPENING_FLOOR,
  URGENT_VISIBILITY_CAP_MIN, URGENT_VISIBILITY_CAP_MAX, URGENT_VISIBILITY_CAP_RATIO,
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

// ── Requirement 3: renewal awareness ────────────────────────────────────────

describe('renewalDampeningFactor', () => {
  it('is 1 (no discount) for a need that has never been renewed', () => {
    expect(renewalDampeningFactor(0)).toBe(1);
  })

  it('strictly decreases with each additional renewal generation', () => {
    const g0 = renewalDampeningFactor(0);
    const g1 = renewalDampeningFactor(1);
    const g2 = renewalDampeningFactor(2);
    expect(g1).toBeLessThan(g0);
    expect(g2).toBeLessThan(g1);
  })

  it('matches the documented per-generation discount exactly at generation 1', () => {
    expect(renewalDampeningFactor(1)).toBeCloseTo(1 - RENEWAL_DAMPENING_PER_GENERATION, 6);
  })

  it('never drops below the configured floor, however many times renewed', () => {
    expect(renewalDampeningFactor(50)).toBe(RENEWAL_DAMPENING_FLOOR);
    expect(renewalDampeningFactor(1000)).toBe(RENEWAL_DAMPENING_FLOOR);
  })

  it('treats a negative generation the same as zero rather than boosting it', () => {
    expect(renewalDampeningFactor(-5)).toBe(1);
  })
})

// ── Requirement 6: visibility cap ───────────────────────────────────────────

describe('urgencyVisibilityCap', () => {
  it('never goes below the configured minimum, even for a tiny page', () => {
    expect(urgencyVisibilityCap(1)).toBeGreaterThanOrEqual(URGENT_VISIBILITY_CAP_MIN);
    expect(urgencyVisibilityCap(0)).toBeGreaterThanOrEqual(URGENT_VISIBILITY_CAP_MIN);
  })

  it('never exceeds the configured maximum, even for a huge page', () => {
    expect(urgencyVisibilityCap(10_000)).toBeLessThanOrEqual(URGENT_VISIBILITY_CAP_MAX);
  })

  it('scales with page size within the configured ratio, between the bounds', () => {
    // Pick a page size where ratio * size lands strictly between min and max.
    const size = Math.round((URGENT_VISIBILITY_CAP_MIN + 1) / URGENT_VISIBILITY_CAP_RATIO);
    const cap = urgencyVisibilityCap(size);
    expect(cap).toBe(Math.ceil(size * URGENT_VISIBILITY_CAP_RATIO));
  })
})

describe('selectBoostedWithinCap', () => {
  it('keeps every boosted need when the cap is not reached', () => {
    const items = [{ id: 'a', boost: 0.1 }, { id: 'b', boost: 0.2 }];
    const allowed = selectBoostedWithinCap(items, 5);
    expect(allowed.has('a')).toBe(true);
    expect(allowed.has('b')).toBe(true);
  })

  it('keeps the strongest N and drops the rest once the cap is reached', () => {
    const items = [
      { id: 'low', boost: 0.05 },
      { id: 'mid', boost: 0.1 },
      { id: 'high', boost: 0.2 },
    ];
    const allowed = selectBoostedWithinCap(items, 2);
    expect(allowed.has('high')).toBe(true);
    expect(allowed.has('mid')).toBe(true);
    expect(allowed.has('low')).toBe(false);
    expect(allowed.size).toBe(2);
  })

  it('ignores needs with zero or negative boost entirely — nothing to cap', () => {
    const items = [{ id: 'a', boost: 0 }, { id: 'b', boost: -1 }];
    expect(selectBoostedWithinCap(items, 5).size).toBe(0);
  })

  it('a cap of zero allows nothing through, regardless of boost size', () => {
    const items = [{ id: 'a', boost: 0.9 }];
    expect(selectBoostedWithinCap(items, 0).size).toBe(0);
  })
})

// ── Requirement 4: graceful fallback ─────────────────────────────────────────

describe('graceful fallback — low confidence never penalizes, only withholds boost', () => {
  it('urgencyRankContribution is exactly 0, never negative, at zero confidence', () => {
    const need = { isUrgent: true, urgencyConfidence: 0, deadline: h(2), status: 'OPEN' };
    expect(urgencyRankContribution(need, 0)).toBe(0);
  })

  it('urgencyRankContribution matches computeUrgencyBoost + rescueScoreBonus exactly — single source of truth', () => {
    const need = { isUrgent: true, urgencyConfidence: 0.6, deadline: h(3), status: 'OPEN' };
    const expected = computeUrgencyBoost(need) + rescueScoreBonus(computeRescueStage(need, 0));
    expect(urgencyRankContribution(need, 0)).toBeCloseTo(expected, 9);
  })

  it('a barely-justified need still gets counted, not rejected — just a small nudge', () => {
    const need = { isUrgent: true, urgencyConfidence: 0.01, deadline: h(1), status: 'OPEN' };
    const contribution = urgencyRankContribution(need, 0);
    expect(contribution).toBeGreaterThanOrEqual(0);
    // Never throws, never returns null/undefined — the need stays fully
    // scoreable through the normal pipeline.
    expect(typeof contribution).toBe('number');
  })
})
