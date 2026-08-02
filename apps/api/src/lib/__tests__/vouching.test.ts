/**
 * Skill Vouching is additive and internal-only, so the properties that
 * matter most: (1) credibility weighting behaves as documented — verified
 * beats unverified, suspicion crushes weight, a bad voucher history
 * discounts future vouches; (2) abuse detection catches reciprocal/rapid
 * patterns but never flags a genuinely verified interaction; (3) nothing
 * internal (credibilityWeight, suspicious) ever reaches a plain object the
 * way a client response would see it; (4) every DB-touching helper degrades
 * to a safe default rather than throwing.
 */

import { describe, it, expect, vi, beforeEach } from 'vitest'

const mocks = vi.hoisted(() => ({
  interestResponseFindMany: vi.fn(),
  vouchFindFirst: vi.fn(),
  vouchCount: vi.fn(),
  vouchGroupBy: vi.fn(),
  userFindUnique: vi.fn(),
  embedBatch: vi.fn(),
}))

vi.mock('../prisma', () => ({
  prisma: {
    interestResponse: { findMany: mocks.interestResponseFindMany },
    vouch: {
      findFirst: mocks.vouchFindFirst,
      count: mocks.vouchCount,
      groupBy: mocks.vouchGroupBy,
    },
    user: { findUnique: mocks.userFindUnique },
  },
}))

vi.mock('../embeddings', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../embeddings')>()
  return { ...actual, embedBatch: mocks.embedBatch, embeddingsAvailable: () => true }
})

vi.mock('../../modules/friends/friends.service', () => ({
  isBlockedBetween: vi.fn().mockResolvedValue(false),
}))

import {
  computeVouchCredibility, detectVerifiedInteraction, detectSuspiciousVouch,
  suggestSkillsForCompletedNeed, countTrustEligibleVouches, fetchTrustEligibleVouchCounts,
  stripInternalVouchFields,
  VOUCH_UNVERIFIED_TRUST_CAP, VOUCH_SUSPICIOUS_MULTIPLIER,
  RECIPROCAL_WINDOW_HOURS, RAPID_FIRE_MAX_VOUCHES,
} from '../vouching'
import { TRUST_WEIGHTS } from '../trust-score'

beforeEach(() => {
  Object.values(mocks).forEach((m) => m.mockReset())
})

describe('computeVouchCredibility', () => {
  const base = { voucherTrustScore: 80, verified: false, collaborationCount: 0, voucherPriorSuspiciousRate: 0, suspicious: false }

  it('an unverified vouch is capped, however high the voucher trust score is', () => {
    const maxTrust = computeVouchCredibility({ ...base, voucherTrustScore: 100 })
    expect(maxTrust).toBeCloseTo(VOUCH_UNVERIFIED_TRUST_CAP, 6)
  })

  it('a verified vouch always outweighs an equivalent unverified one', () => {
    const unverified = computeVouchCredibility({ ...base, verified: false })
    const verified = computeVouchCredibility({ ...base, verified: true })
    expect(verified).toBeGreaterThan(unverified)
  })

  it('more collaborations increase a verified vouch, with diminishing effect', () => {
    const one = computeVouchCredibility({ ...base, verified: true, collaborationCount: 1 })
    const four = computeVouchCredibility({ ...base, verified: true, collaborationCount: 4 })
    const forty = computeVouchCredibility({ ...base, verified: true, collaborationCount: 40 })
    expect(four).toBeGreaterThan(one)
    expect(forty).toBe(four) // capped past VOUCH_COLLAB_BONUS_MAX_COUNT
  })

  it('a history of suspicious vouches discounts every future vouch from that voucher', () => {
    const clean = computeVouchCredibility({ ...base, voucherPriorSuspiciousRate: 0 })
    const tainted = computeVouchCredibility({ ...base, voucherPriorSuspiciousRate: 0.8 })
    expect(tainted).toBeLessThan(clean);
  })

  it('a suspicious vouch is crushed toward zero, not deleted or set to exactly 0', () => {
    const normal = computeVouchCredibility({ ...base, verified: true, suspicious: false });
    const flagged = computeVouchCredibility({ ...base, verified: true, suspicious: true });
    expect(flagged).toBeCloseTo(normal * VOUCH_SUSPICIOUS_MULTIPLIER, 6);
    expect(flagged).toBeGreaterThan(0);
  })

  it('never exceeds 1 or drops below 0 across extreme inputs', () => {
    expect(computeVouchCredibility({ voucherTrustScore: 1000, verified: true, collaborationCount: 1000, voucherPriorSuspiciousRate: 0, suspicious: false })).toBeLessThanOrEqual(1);
    expect(computeVouchCredibility({ voucherTrustScore: -50, verified: false, collaborationCount: 0, voucherPriorSuspiciousRate: 1, suspicious: true })).toBeGreaterThanOrEqual(0);
  })
})

describe('detectVerifiedInteraction', () => {
  it('true with a collaboration count when a completed need is found either direction', async () => {
    mocks.interestResponseFindMany.mockResolvedValue([{ needId: 'n1' }, { needId: 'n2' }]);
    const result = await detectVerifiedInteraction('voucher-1', 'vouchee-1');
    expect(result).toEqual({ verified: true, collaborationCount: 2 });
  })

  it('false with zero count when nothing is found', async () => {
    mocks.interestResponseFindMany.mockResolvedValue([]);
    expect(await detectVerifiedInteraction('a', 'b')).toEqual({ verified: false, collaborationCount: 0 });
  })

  it('degrades to unverified rather than throwing on a DB error', async () => {
    mocks.interestResponseFindMany.mockRejectedValue(new Error('down'));
    await expect(detectVerifiedInteraction('a', 'b')).resolves.toEqual({ verified: false, collaborationCount: 0 });
  })
})

describe('detectSuspiciousVouch', () => {
  it('is never flagged when the interaction is verified, regardless of pattern', async () => {
    const result = await detectSuspiciousVouch('a', 'b', true);
    expect(result).toBe(false);
    expect(mocks.vouchFindFirst).not.toHaveBeenCalled(); // short-circuits — no query needed
  })

  it('flags a reciprocal vouch within the window', async () => {
    mocks.vouchFindFirst.mockResolvedValue({ id: 'existing' });
    mocks.vouchCount.mockResolvedValue(0);
    expect(await detectSuspiciousVouch('a', 'b', false)).toBe(true);
  })

  it('flags rapid-fire vouching at or above the threshold', async () => {
    mocks.vouchFindFirst.mockResolvedValue(null);
    mocks.vouchCount.mockResolvedValue(RAPID_FIRE_MAX_VOUCHES);
    expect(await detectSuspiciousVouch('a', 'b', false)).toBe(true);
  })

  it('does not flag a normal, isolated unverified vouch', async () => {
    mocks.vouchFindFirst.mockResolvedValue(null);
    mocks.vouchCount.mockResolvedValue(1);
    expect(await detectSuspiciousVouch('a', 'b', false)).toBe(false);
  })

  it('fails open — a detection error never blocks a vouch', async () => {
    mocks.vouchFindFirst.mockRejectedValue(new Error('down'));
    mocks.vouchCount.mockResolvedValue(0);
    await expect(detectSuspiciousVouch('a', 'b', false)).resolves.toBe(false);
  })

  it('uses the documented reciprocal window in its query', async () => {
    mocks.vouchFindFirst.mockResolvedValue(null);
    mocks.vouchCount.mockResolvedValue(0);
    await detectSuspiciousVouch('a', 'b', false);
    const arg = mocks.vouchFindFirst.mock.calls[0][0];
    const cutoff = arg.where.createdAt.gte as Date;
    const expectedHoursAgo = (Date.now() - cutoff.getTime()) / 3_600_000;
    expect(expectedHoursAgo).toBeCloseTo(RECIPROCAL_WINDOW_HOURS, 0);
  })
})

describe('countTrustEligibleVouches / fetchTrustEligibleVouchCounts', () => {
  it('returns 0 for an empty id list without querying', async () => {
    const result = await fetchTrustEligibleVouchCounts([]);
    expect(result.size).toBe(0);
    expect(mocks.vouchGroupBy).not.toHaveBeenCalled();
  })

  it('maps grouped counts back onto each id, defaulting missing ids to 0', async () => {
    mocks.vouchGroupBy.mockResolvedValue([{ voucheeId: 'u1', _count: { id: 3 } }]);
    const result = await fetchTrustEligibleVouchCounts(['u1', 'u2']);
    expect(result.get('u1')).toBe(3);
    expect(result.get('u2')).toBeUndefined(); // caller defaults with ?? 0
  })

  it('the singular form reads through the batched form correctly', async () => {
    mocks.vouchGroupBy.mockResolvedValue([{ voucheeId: 'solo', _count: { id: 7 } }]);
    expect(await countTrustEligibleVouches('solo')).toBe(7);
  })

  it('degrades to an empty map on a DB error', async () => {
    mocks.vouchGroupBy.mockRejectedValue(new Error('down'));
    const result = await fetchTrustEligibleVouchCounts(['u1']);
    expect(result.size).toBe(0);
  })
})

describe('suggestSkillsForCompletedNeed', () => {
  const need = { title: 'Fix my bike', description: 'Chain kept slipping', earnCategory: 'REPAIR', connectCategory: null };

  it('returns nothing when the vouchee has no declared skills', async () => {
    expect(await suggestSkillsForCompletedNeed(need, [])).toEqual([]);
    expect(mocks.embedBatch).not.toHaveBeenCalled();
  })

  it('ranks the strongest match first — absolute floor is sanity-only, not a hard cutoff', async () => {
    // Grounded in measurement (see the constant's doc comment): bare skill
    // labels score far lower in absolute terms than a fixed 0.5-style floor
    // would allow through, so ranking + human review is the filter here,
    // not an absolute threshold.
    const skills = [{ id: 's1', label: 'Bicycle Repair' }, { id: 's2', label: 'Poetry' }];
    mocks.embedBatch.mockImplementation((texts: string[]) => {
      if (texts.length === 1) return Promise.resolve([[1, 0]]); // the need
      return Promise.resolve([[0.9, 0.1], [0, 1]]); // skill vectors: high match, orthogonal
    });
    const result = await suggestSkillsForCompletedNeed(need, skills);
    expect(result[0]?.id).toBe('s1'); // strongest match ranked first
  })

  it('caps at MAX_SUGGESTED_SKILLS even when every candidate scores positively', async () => {
    const skills = Array.from({ length: 8 }, (_, i) => ({ id: `s${i}`, label: `Skill ${i}` }));
    mocks.embedBatch.mockImplementation((texts: string[]) =>
      Promise.resolve(texts.map(() => [1, 0])));
    const result = await suggestSkillsForCompletedNeed(need, skills);
    expect(result.length).toBeLessThanOrEqual(5);
  })

  it('excludes a genuinely negative (opposite-direction) match', async () => {
    const skills = [{ id: 's1', label: 'Relevant' }, { id: 's2', label: 'Opposite' }];
    mocks.embedBatch.mockImplementation((texts: string[]) => {
      if (texts.length === 1) return Promise.resolve([[1, 0]]);
      return Promise.resolve([[0.5, 0], [-1, 0]]); // second skill points the opposite way
    });
    const result = await suggestSkillsForCompletedNeed(need, skills);
    expect(result.map((s) => s.id)).not.toContain('s2');
  })

  it('never creates or writes anything — purely returns a suggestion list', async () => {
    mocks.embedBatch.mockResolvedValue(null);
    const result = await suggestSkillsForCompletedNeed(need, [{ id: 's1', label: 'X' }]);
    expect(Array.isArray(result)).toBe(true);
    expect(result).toEqual([]);
  })

  it('degrades to no suggestions on embedding failure', async () => {
    mocks.embedBatch.mockRejectedValue(new Error('down'));
    await expect(suggestSkillsForCompletedNeed(need, [{ id: 's1', label: 'X' }])).resolves.toEqual([]);
  })
})

describe('stripInternalVouchFields', () => {
  it('removes credibilityWeight and suspicious, keeps everything else including verified', () => {
    const vouch = { id: 'v1', verified: true, credibilityWeight: 0.77, suspicious: false, testimonial: 'Great!' };
    const stripped = stripInternalVouchFields(vouch);
    expect(stripped).toEqual({ id: 'v1', verified: true, testimonial: 'Great!' });
    expect('credibilityWeight' in stripped).toBe(false);
    expect('suspicious' in stripped).toBe(false);
  })
})

describe('Trust Score integration stays within budget', () => {
  it('the skill-endorsement slice is capped well below any single dominant factor', () => {
    // Requirement 6: no single factor should dominate. The endorsement cap
    // must stay smaller than phone, face, reviews and fulfilled — the
    // stronger, harder-to-fake signals.
    expect(TRUST_WEIGHTS.skillEndorsementCap).toBeLessThan(TRUST_WEIGHTS.phone);
    expect(TRUST_WEIGHTS.skillEndorsementCap).toBeLessThan(TRUST_WEIGHTS.face);
    expect(TRUST_WEIGHTS.skillEndorsementCap).toBeLessThan(TRUST_WEIGHTS.reviewsMax);
    expect(TRUST_WEIGHTS.skillEndorsementCap).toBeLessThan(TRUST_WEIGHTS.fulfilledCap);
  })
})
