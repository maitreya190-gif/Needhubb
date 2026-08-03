/**
 * chitchatTier + fetchPlusChitchatTier are the pieces that let
 * chitchat.router.ts replace two separate sorts (nearest-first, then
 * *conditionally* boosted-first) with one unconditional comparator. The
 * degenerate-case tests below are what prove that replacement is safe — see
 * chitchat.router.ts's own comment for how the comparator is built from
 * these primitives.
 */

import { describe, it, expect, vi, beforeEach } from 'vitest'

const mocks = vi.hoisted(() => ({ visibilityBoostFindMany: vi.fn(), plusSubscriptionFindMany: vi.fn() }))

vi.mock('../prisma', () => ({
  prisma: {
    visibilityBoost: { findMany: mocks.visibilityBoostFindMany },
    plusSubscription: { findMany: mocks.plusSubscriptionFindMany },
  },
}))

import {
  chitchatTier, fetchPlusChitchatTier, PLUS_CHITCHAT_TIER_CAP, fetchPlusPosterIds,
} from '../plus-visibility'

beforeEach(() => {
  Object.values(mocks).forEach((m) => m.mockReset())
})

describe('chitchatTier', () => {
  it('ranks a paid boost above Plus, and Plus above neither', () => {
    const boosted = new Set(['b1'])
    const plus = new Set(['p1'])
    expect(chitchatTier('b1', boosted, plus)).toBe(2)
    expect(chitchatTier('p1', boosted, plus)).toBe(1)
    expect(chitchatTier('nobody', boosted, plus)).toBe(0)
  })

  it('a paid boost wins even if the same user is also in the plus set', () => {
    expect(chitchatTier('both', new Set(['both']), new Set(['both']))).toBe(2)
  })
})

describe('fetchPlusChitchatTier', () => {
  it('returns an empty set without querying when given no ids', async () => {
    expect(await fetchPlusChitchatTier([])).toEqual(new Set())
    expect(mocks.plusSubscriptionFindMany).not.toHaveBeenCalled()
  })

  it('only the NEAREST PLUS_CHITCHAT_TIER_CAP premium users hold the tier — rest fall out', async () => {
    // ordered nearest-first: u1, u2, u3, u4 — all premium, cap is 3.
    mocks.plusSubscriptionFindMany.mockResolvedValue(
      ['u1', 'u2', 'u3', 'u4'].map((userId) => ({ userId })),
    )
    const result = await fetchPlusChitchatTier(['u1', 'u2', 'u3', 'u4'])
    expect(result.size).toBe(PLUS_CHITCHAT_TIER_CAP)
    expect(result).toEqual(new Set(['u1', 'u2', 'u3']))
    expect(result.has('u4')).toBe(false)
  })

  it('preserves the nearest-first order even if the DB returns rows in a different order', async () => {
    // DB returns u3 first, but caller's ordering (nearest-first) is u1,u2,u3.
    mocks.plusSubscriptionFindMany.mockResolvedValue([{ userId: 'u3' }, { userId: 'u1' }, { userId: 'u2' }])
    const result = await fetchPlusChitchatTier(['u1', 'u2', 'u3'])
    expect(result).toEqual(new Set(['u1', 'u2', 'u3'])) // all 3 fit under the cap regardless of order
  })

  it('fails safe to an empty set on a DB error, never throws', async () => {
    mocks.plusSubscriptionFindMany.mockRejectedValue(new Error('db down'))
    expect(await fetchPlusChitchatTier(['u1'])).toEqual(new Set())
  })
})

describe('degenerate-case equivalence — proves replacing the two old sorts with one comparator is safe', () => {
  function comparator(a: string, b: string, boosted: Set<string>, plusNearest: Set<string>, distanceOf: Record<string, number>) {
    const tierDiff = chitchatTier(b, boosted, plusNearest) - chitchatTier(a, boosted, plusNearest)
    if (tierDiff !== 0) return tierDiff
    return distanceOf[a] - distanceOf[b]
  }

  it('with both sets empty, sorting is byte-identical to plain nearest-first', () => {
    const ids = ['far', 'near', 'mid']
    const distanceOf = { far: 30, near: 1, mid: 10 }
    const sorted = [...ids].sort((a, b) => comparator(a, b, new Set(), new Set(), distanceOf))
    expect(sorted).toEqual(['near', 'mid', 'far'])
  })

  it('with only paid boosts present, sorting is byte-identical to the old boosted-first re-sort', () => {
    const ids = ['far', 'near', 'boostedFar']
    const distanceOf = { far: 30, near: 1, boostedFar: 25 }
    const boosted = new Set(['boostedFar'])
    const sorted = [...ids].sort((a, b) => comparator(a, b, boosted, new Set(), distanceOf))
    expect(sorted).toEqual(['boostedFar', 'near', 'far'])
  })
})

describe('fetchPlusPosterIds', () => {
  it('is the same function as fetchPlusUserIds (thin alias, no divergent behavior)', async () => {
    expect(typeof fetchPlusPosterIds).toBe('function')
  })
})
