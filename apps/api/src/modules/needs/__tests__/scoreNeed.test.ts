/**
 * The single most important guarantee for this feature: scoreNeed must
 * produce the exact same number for a non-urgent need as it did before
 * Urgency Mode existed. Every need created before this shipped, and every
 * need that never opts in, has isUrgent=false — so this pins that the
 * existing ranking algorithm (relevance, proximity, freshness, trust) is
 * untouched, and that urgency only ever adds on top for needs that opt in.
 */

// needs.router.ts creates the Prisma client at module-load time (it is never
// called in this file — scoreNeed is pure), so DATABASE_URL must be present
// for the import itself to succeed. Same convention as skill-matching.test.ts.
import 'dotenv/config'
import { describe, it, expect } from 'vitest'
import { scoreNeed } from '../needs.router'

const baseNeed = {
  title: 'Need a tutor', description: 'Algebra help', createdAt: new Date(),
  earnCategory: 'TUTORING', connectCategory: null, needType: 'EARN',
}
const notUrgent = { isUrgent: false, urgencyConfidence: null, deadline: null, status: 'OPEN' }
const urgentAndActive = {
  isUrgent: true, urgencyConfidence: 0.9,
  deadline: new Date(Date.now() + 2 * 3_600_000), status: 'OPEN',
}

function score(need: typeof baseNeed & typeof notUrgent, semantic: number | null) {
  return scoreNeed(need, 5, [], semantic, 40, 0)
}

describe('non-urgent needs score exactly as before Urgency Mode existed', () => {
  it('embeddings-mode score matches the documented EARN weights precisely', () => {
    // 0.60 semantic + 0.25 proximity + 0.15 freshness, semantic=0.8 (cosine 0.6),
    // distance=5km -> proximity = 1 - 5/30, freshness ~= 1 (just created).
    const s = score({ ...baseNeed, ...notUrgent }, 0.6)
    const semanticScore = (0.6 + 1) / 2
    const proximityScore = 1 - 5 / 30
    const expected = 0.60 * semanticScore + 0.25 * proximityScore + 0.15 * 1
    expect(s).toBeCloseTo(expected, 5)
  })

  it('heuristic-mode score matches the documented EARN weights precisely', () => {
    const s = score({ ...baseNeed, ...notUrgent }, null)
    const proximityScore = 1 - 5 / 30
    const expected = 0.55 * 0.5 + 0.30 * proximityScore + 0.15 * 1
    expect(s).toBeCloseTo(expected, 5)
  })

  it('CONNECT needs still fold in trust score exactly as before', () => {
    const connectNeed = { ...baseNeed, needType: 'CONNECT', earnCategory: null, connectCategory: 'HOBBY', ...notUrgent }
    const s = scoreNeed(connectNeed, 5, [], 0.6, 40, 0)
    const semanticScore = (0.6 + 1) / 2
    const proximityScore = 1 - 5 / 30
    const expected = 0.45 * semanticScore + 0.20 * proximityScore + 0.15 * 1 + 0.20 * 0.4
    expect(s).toBeCloseTo(expected, 5)
  })

  it('an isUrgent=true need with no confidence yet scores identically to non-urgent', () => {
    // The window between creation and the async evaluation landing.
    const pending = { isUrgent: true, urgencyConfidence: null, deadline: new Date(Date.now() + 3_600_000), status: 'OPEN' }
    const withoutUrgency = score({ ...baseNeed, ...notUrgent }, 0.6)
    const pendingScore = scoreNeed({ ...baseNeed, ...pending }, 5, [], 0.6, 40, 0)
    expect(pendingScore).toBe(withoutUrgency)
  })
})

describe('urgency only ever adds on top — never replaces the base score', () => {
  it('an urgent, evaluated, open need scores strictly higher than the same need without urgency', () => {
    const without = score({ ...baseNeed, ...notUrgent }, 0.6)
    const withUrgency = scoreNeed({ ...baseNeed, ...urgentAndActive }, 5, [], 0.6, 40, 0)
    expect(withUrgency).toBeGreaterThan(without)
  })

  it('urgency contributes nothing once the need is FULFILLED — matches the explicit ask', () => {
    const fulfilled = { ...urgentAndActive, status: 'FULFILLED' }
    const withFulfilled = scoreNeed({ ...baseNeed, ...fulfilled }, 5, [], 0.6, 40, 0)
    const withoutUrgency = score({ ...baseNeed, ...notUrgent }, 0.6)
    expect(withFulfilled).toBe(withoutUrgency)
  })

  it('a rescued need (stage 3, zero responses, imminent deadline) scores higher than the same need with plenty of responses', () => {
    const imminent = {
      isUrgent: true, urgencyConfidence: 0.6,
      deadline: new Date(Date.now() + 2 * 3_600_000), status: 'OPEN',
    }
    const rescued = scoreNeed({ ...baseNeed, ...imminent }, 5, [], 0.6, 40, 0)
    const notRescued = scoreNeed({ ...baseNeed, ...imminent }, 5, [], 0.6, 40, 5)
    expect(rescued).toBeGreaterThan(notRescued)
  })
})

describe('paid visibility boost (7th, optional argument — see lib/visibility-boost.ts)', () => {
  it('omitting it entirely scores exactly like passing 0 — existing callers are untouched', () => {
    const omitted = score({ ...baseNeed, ...notUrgent }, 0.6)
    const explicitZero = scoreNeed({ ...baseNeed, ...notUrgent }, 5, [], 0.6, 40, 0, 0)
    expect(omitted).toBe(explicitZero)
  })

  it('adds on top of the organic score rather than replacing it', () => {
    const without = score({ ...baseNeed, ...notUrgent }, 0.6)
    const boosted = scoreNeed({ ...baseNeed, ...notUrgent }, 5, [], 0.6, 40, 0, 2.0)
    expect(boosted).toBeCloseTo(without + 2.0, 5)
  })

  it('stacks additively with an active urgency boost rather than one overriding the other', () => {
    const urgencyOnly = scoreNeed({ ...baseNeed, ...urgentAndActive }, 5, [], 0.6, 40, 0)
    const urgencyAndPaid = scoreNeed({ ...baseNeed, ...urgentAndActive }, 5, [], 0.6, 40, 0, 2.0)
    expect(urgencyAndPaid).toBeCloseTo(urgencyOnly + 2.0, 5)
  })
})
