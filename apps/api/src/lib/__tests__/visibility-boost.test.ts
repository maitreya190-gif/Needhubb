/**
 * Paid visibility boosts read the existing VisibilityBoost model — the two
 * things worth pinning are: (1) an active boost is found by the right
 * (targetType, targetId, unexpired) combination and nothing else leaks in,
 * and (2) every read degrades to empty/safe on a DB error rather than
 * breaking the feed or the chitchat roster that call it.
 */

import { describe, it, expect, vi, beforeEach } from 'vitest'

const mocks = vi.hoisted(() => ({ visibilityBoostFindMany: vi.fn() }))

vi.mock('../prisma', () => ({
  prisma: { visibilityBoost: { findMany: mocks.visibilityBoostFindMany } },
}))

import {
  fetchActiveNeedBoosts, fetchActiveChitchatBoosts, boostVisibilityCap,
  BOOST_VISIBILITY_CAP_MIN, BOOST_VISIBILITY_CAP_MAX, CHITCHAT_BOOST_TIERS,
} from '../visibility-boost'

beforeEach(() => {
  Object.values(mocks).forEach((m) => m.mockReset())
})

describe('fetchActiveNeedBoosts', () => {
  it('returns an empty set without querying when given no ids', async () => {
    expect(await fetchActiveNeedBoosts([])).toEqual(new Set())
    expect(mocks.visibilityBoostFindMany).not.toHaveBeenCalled()
  })

  it('queries only NEED-typed, unexpired boosts among the given ids', async () => {
    mocks.visibilityBoostFindMany.mockResolvedValue([{ targetId: 'n1' }])
    const result = await fetchActiveNeedBoosts(['n1', 'n2'])
    expect(result).toEqual(new Set(['n1']))
    const where = mocks.visibilityBoostFindMany.mock.calls[0][0].where
    expect(where.targetType).toBe('NEED')
    expect(where.targetId.in).toEqual(['n1', 'n2'])
    expect(where.expiresAt.gt).toBeInstanceOf(Date)
  })

  it('fails safe to an empty set on a DB error, never throws', async () => {
    mocks.visibilityBoostFindMany.mockRejectedValue(new Error('db down'))
    expect(await fetchActiveNeedBoosts(['n1'])).toEqual(new Set())
  })
})

describe('fetchActiveChitchatBoosts', () => {
  it('returns an empty set without querying when given no ids', async () => {
    expect(await fetchActiveChitchatBoosts([])).toEqual(new Set())
    expect(mocks.visibilityBoostFindMany).not.toHaveBeenCalled()
  })

  it('queries only PROFILE-typed, unexpired boosts among the given ids', async () => {
    mocks.visibilityBoostFindMany.mockResolvedValue([{ targetId: 'u1' }])
    const result = await fetchActiveChitchatBoosts(['u1', 'u2'])
    expect(result).toEqual(new Set(['u1']))
    const where = mocks.visibilityBoostFindMany.mock.calls[0][0].where
    expect(where.targetType).toBe('PROFILE')
    expect(where.targetId.in).toEqual(['u1', 'u2'])
  })

  it('fails safe to an empty set on a DB error, never throws', async () => {
    mocks.visibilityBoostFindMany.mockRejectedValue(new Error('db down'))
    expect(await fetchActiveChitchatBoosts(['u1'])).toEqual(new Set())
  })
})

describe('boostVisibilityCap', () => {
  it('never drops below the configured minimum, even for a tiny page', () => {
    expect(boostVisibilityCap(1)).toBe(BOOST_VISIBILITY_CAP_MIN);
  })

  it('never exceeds the configured maximum, even for a huge page', () => {
    expect(boostVisibilityCap(1000)).toBe(BOOST_VISIBILITY_CAP_MAX)
  })

  it('scales with page size in between the bounds', () => {
    const cap = boostVisibilityCap(20) // 20 * 0.2 = 4, within [2, 6]
    expect(cap).toBe(4)
  })
})

describe('CHITCHAT_BOOST_TIERS', () => {
  it('never offers a duration longer than chitchat availability itself (12h max)', () => {
    for (const tier of Object.values(CHITCHAT_BOOST_TIERS)) {
      expect(tier.hours).toBeLessThanOrEqual(12)
    }
  })

  it('costs increase with duration — no tier is a strictly worse deal than a cheaper one', () => {
    const tiers = Object.values(CHITCHAT_BOOST_TIERS).sort((a, b) => a.hours - b.hours)
    for (let i = 1; i < tiers.length; i++) {
      expect(tiers[i].cost).toBeGreaterThan(tiers[i - 1].cost)
      expect(tiers[i].hours).toBeGreaterThan(tiers[i - 1].hours)
    }
  })
})
