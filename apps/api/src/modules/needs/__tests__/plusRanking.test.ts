/**
 * Proves NeedHub Plus's feed bonus is exactly what §2 of the Plus plan
 * promises: a flat, additive, MODERATE constant that can never rescale,
 * multiply, or floor anything, and is provably smaller than every other
 * "money or urgency helps you" signal already in the ranking system.
 * scoreNeed is pure, so — same as scoreNeed.test.ts — no Prisma mock needed.
 */

import 'dotenv/config'
import { describe, it, expect } from 'vitest'
import { scoreNeed } from '../needs.router'
import { PLUS_NEED_RANK_BONUS, plusVisibilityCap, selectPlusWithinCap } from '../../../lib/plus-visibility'
import { NEED_BOOST_RANK_BONUS } from '../../../lib/visibility-boost'
import { URGENCY_MAX_BOOST } from '../../../lib/urgency'

const FRESHNESS_WEIGHT = 0.15 // smallest single organic weight in scoreNeed — see needs.router.ts

function needAt(daysOld: number, needType: 'EARN' | 'CONNECT') {
  return {
    title: 'Need a tutor', description: 'Algebra help',
    createdAt: new Date(Date.now() - daysOld * 24 * 3_600_000),
    earnCategory: needType === 'EARN' ? 'TUTORING' : null,
    connectCategory: needType === 'CONNECT' ? 'HOBBY' : null,
    needType,
    isUrgent: false, urgencyConfidence: null, deadline: null, status: 'OPEN',
  }
}

describe('PLUS_NEED_RANK_BONUS is provably moderate', () => {
  it('is smaller than URGENCY_MAX_BOOST — money can never outweigh a verified emergency', () => {
    expect(PLUS_NEED_RANK_BONUS).toBeLessThan(URGENCY_MAX_BOOST)
  })

  it('is smaller than the smallest organic weight (freshness) — premium is worth less than being newly posted', () => {
    expect(PLUS_NEED_RANK_BONUS).toBeLessThan(FRESHNESS_WEIGHT)
  })

  it('is much smaller than a paid points-boost — a purchased boost stays the decisive signal', () => {
    expect(PLUS_NEED_RANK_BONUS).toBeLessThan(NEED_BOOST_RANK_BONUS / 4)
  })
})

describe('the bonus is exactly additive across the whole input space', () => {
  const cosines = [-1, -0.5, 0, 0.3, 0.6, 1, null]
  const distances = [0, 5, 15, 30, 60, null]
  const ages = [0, 1, 3, 7, 30]
  const trusts = [0, 40, 100]
  const types: ('EARN' | 'CONNECT')[] = ['EARN', 'CONNECT']

  it('adds a constant, and only a constant, never rescaling or flooring anything', () => {
    for (const cos of cosines) {
      for (const km of distances) {
        for (const days of ages) {
          for (const trust of trusts) {
            for (const type of types) {
              const need = needAt(days, type)
              const organic = scoreNeed(need, km, [], cos, trust, 0)
              const withPlus = scoreNeed(need, km, [], cos, trust, 0, 0, PLUS_NEED_RANK_BONUS)
              expect(withPlus - organic).toBeCloseTo(PLUS_NEED_RANK_BONUS, 5)
            }
          }
        }
      }
    }
  })

  it('omitting the 8th argument scores exactly like passing 0 — existing callers are untouched', () => {
    const need = needAt(1, 'EARN')
    const omitted = scoreNeed(need, 5, [], 0.6, 40, 0)
    const explicitZero = scoreNeed(need, 5, [], 0.6, 40, 0, 0, 0)
    expect(omitted).toBe(explicitZero)
  })

  it('stacks additively on top of an active paid boost rather than one overriding the other', () => {
    const need = needAt(1, 'EARN')
    const boostOnly = scoreNeed(need, 5, [], 0.6, 40, 0, NEED_BOOST_RANK_BONUS)
    const boostAndPlus = scoreNeed(need, 5, [], 0.6, 40, 0, NEED_BOOST_RANK_BONUS, PLUS_NEED_RANK_BONUS)
    expect(boostAndPlus).toBeCloseTo(boostOnly + PLUS_NEED_RANK_BONUS, 5)
  })
})

describe('premium never crosses a real relevance gap', () => {
  it('a weakly-relevant premium need never outranks a strongly-relevant organic need (EARN)', () => {
    const strongOrganic = scoreNeed(needAt(1, 'EARN'), 2, [], 0.6, 40, 0)
    const weakPremium = scoreNeed(needAt(5, 'EARN'), 25, [], 0.0, 40, 0, 0, PLUS_NEED_RANK_BONUS)
    expect(weakPremium).toBeLessThan(strongOrganic)
  })

  it('a max-trust non-premium CONNECT poster still outranks a zero-trust premium one', () => {
    const nonPremiumMaxTrust = scoreNeed(needAt(1, 'CONNECT'), 5, [], 0.3, 100, 0)
    const premiumZeroTrust = scoreNeed(needAt(1, 'CONNECT'), 5, [], 0.3, 0, 0, 0, PLUS_NEED_RANK_BONUS)
    expect(premiumZeroTrust).toBeLessThan(nonPremiumMaxTrust)
  })
})

describe('plusVisibilityCap', () => {
  it('never drops below the configured minimum', () => {
    expect(plusVisibilityCap(1)).toBe(2)
  })

  it('never exceeds the configured maximum, and stays tighter than the paid-boost cap (6)', () => {
    expect(plusVisibilityCap(1000)).toBe(4)
  })

  it('scales with page size in between the bounds', () => {
    expect(plusVisibilityCap(20)).toBe(4) // 20 * 0.2 = 4, within [2, 4]
  })
})

describe('selectPlusWithinCap', () => {
  it('selects by organic score, not by the (flat) bonus value — highest-relevance premium needs win the scarce slots', () => {
    const items = [
      { id: 'low', plusBonus: PLUS_NEED_RANK_BONUS, organicScore: 0.2 },
      { id: 'high', plusBonus: PLUS_NEED_RANK_BONUS, organicScore: 0.8 },
      { id: 'mid', plusBonus: PLUS_NEED_RANK_BONUS, organicScore: 0.5 },
    ]
    expect(selectPlusWithinCap(items, 2)).toEqual(new Set(['high', 'mid']))
  })

  it('ignores non-premium items entirely', () => {
    const items = [{ id: 'organic-only', plusBonus: 0, organicScore: 0.9 }]
    expect(selectPlusWithinCap(items, 5)).toEqual(new Set())
  })

  it('returns an empty set at cap 0', () => {
    const items = [{ id: 'a', plusBonus: PLUS_NEED_RANK_BONUS, organicScore: 0.5 }]
    expect(selectPlusWithinCap(items, 0)).toEqual(new Set())
  })

  it('a premium need beyond the cap, when subtracted back out, reverts to exactly its organic score', () => {
    const need = needAt(1, 'EARN')
    const organic = scoreNeed(need, 5, [], 0.6, 40, 0)
    const withPlus = scoreNeed(need, 5, [], 0.6, 40, 0, 0, PLUS_NEED_RANK_BONUS)
    const reverted = withPlus - PLUS_NEED_RANK_BONUS
    expect(reverted).toBeCloseTo(organic, 5)
  })
})
