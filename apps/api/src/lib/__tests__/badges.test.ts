/**
 * Badges are the visible claim "this person actually did this", so the rules
 * behind them have to be exact. These tests pin every threshold, and pin the
 * property that matters most: a badge cannot be earned without the underlying
 * fact being true.
 */

import { describe, it, expect } from 'vitest'
import {
  computeBadges,
  earnedBadgeCount,
  BADGE_DEFINITIONS,
  TOTAL_BADGE_COUNT,
  type BadgeInputs,
} from '../badges'
import { computeTrustScore, TRUST_WEIGHTS } from '../trust-score'

/** A user who has done nothing at all. */
const NOBODY: BadgeInputs = {
  emailVerifiedAt: null,
  phoneVerifiedAt: null,
  faceVerifiedAt: null,
  idVerifiedAt: null,
  helpedNeedCount: 0,
  fulfilledPostedCount: 0,
  approvedCertificateCount: 0,
  avgRating: 0,
  ratingCount: 0,
  activatedReferralCount: 0,
}

const NOW = new Date()

function earnedIds(inputs: Partial<BadgeInputs>): string[] {
  return computeBadges({ ...NOBODY, ...inputs })
    .filter((b) => b.earned)
    .map((b) => b.id)
}

describe('a new user earns nothing', () => {
  it('has zero earned badges', () => {
    expect(earnedIds({})).toEqual([])
    expect(earnedBadgeCount(NOBODY)).toBe(0)
  })

  it('still sees every badge, so locked ones read as goals', () => {
    const badges = computeBadges(NOBODY)
    expect(badges).toHaveLength(TOTAL_BADGE_COUNT)
    expect(badges.every((b) => !b.earned)).toBe(true)
  })

  it('gives every locked badge a description saying what it takes', () => {
    for (const b of computeBadges(NOBODY)) {
      expect(b.description.length, `description for "${b.id}"`).toBeGreaterThan(0)
    }
  })
})

describe('verification badges', () => {
  it('email, phone, face and id each unlock only their own badge', () => {
    expect(earnedIds({ emailVerifiedAt: NOW })).toEqual(['email_verified'])
    expect(earnedIds({ phoneVerifiedAt: NOW })).toEqual(['phone_verified'])
    expect(earnedIds({ faceVerifiedAt: NOW })).toEqual(['face_verified'])
    expect(earnedIds({ idVerifiedAt: NOW })).toEqual(['id_verified'])
  })

  it('fully_verified needs all four, not three', () => {
    expect(earnedIds({ emailVerifiedAt: NOW, phoneVerifiedAt: NOW, faceVerifiedAt: NOW }))
      .not.toContain('fully_verified')
    expect(
      earnedIds({ emailVerifiedAt: NOW, phoneVerifiedAt: NOW, faceVerifiedAt: NOW, idVerifiedAt: NOW }),
    ).toContain('fully_verified')
  })
})

describe('helping badges are earned by helping, not by asking', () => {
  it('unlocks at 1, 5, 10 and 25 needs helped with', () => {
    expect(earnedIds({ helpedNeedCount: 1 })).toEqual(['first_help'])
    expect(earnedIds({ helpedNeedCount: 5 })).toEqual(['first_help', 'helping_hand'])
    expect(earnedIds({ helpedNeedCount: 10 }))
      .toEqual(['first_help', 'helping_hand', 'reliable'])
    expect(earnedIds({ helpedNeedCount: 25 }))
      .toEqual(['first_help', 'helping_hand', 'reliable', 'veteran'])
  })

  it('does not unlock one short of a threshold', () => {
    expect(earnedIds({ helpedNeedCount: 4 })).not.toContain('helping_hand')
    expect(earnedIds({ helpedNeedCount: 24 })).not.toContain('veteran')
  })

  it('posting needs never earns a helping badge', () => {
    // Someone who posted 50 needs has not helped anybody.
    expect(earnedIds({ fulfilledPostedCount: 50 })).toEqual(['follows_through'])
  })
})

describe('quality badges need a real sample', () => {
  it('5-star requires at least 5 reviews, not one perfect one', () => {
    expect(earnedIds({ avgRating: 5, ratingCount: 1 })).not.toContain('five_star')
    expect(earnedIds({ avgRating: 5, ratingCount: 5 })).toContain('five_star')
  })

  it('5-star requires a 4.8+ average', () => {
    expect(earnedIds({ avgRating: 4.7, ratingCount: 20 })).not.toContain('five_star')
    expect(earnedIds({ avgRating: 4.8, ratingCount: 20 })).toContain('five_star')
  })

  it('well_reviewed is about volume, regardless of score', () => {
    expect(earnedIds({ avgRating: 2.0, ratingCount: 10 })).toContain('well_reviewed')
  })
})

describe('community badges', () => {
  it('certified needs an approved certificate', () => {
    expect(earnedIds({ approvedCertificateCount: 1 })).toEqual(['certified'])
  })

  it('community_builder needs 3 activated referrals', () => {
    expect(earnedIds({ activatedReferralCount: 2 })).not.toContain('community_builder')
    expect(earnedIds({ activatedReferralCount: 3 })).toContain('community_builder')
  })
})

describe('badge definitions are coherent', () => {
  it('has no duplicate ids — a duplicate would double-count in trust score', () => {
    const ids = BADGE_DEFINITIONS.map((b) => b.id)
    expect(new Set(ids).size).toBe(ids.length)
  })

  it('every badge is reachable by some input', () => {
    const everything: BadgeInputs = {
      emailVerifiedAt: NOW,
      phoneVerifiedAt: NOW,
      faceVerifiedAt: NOW,
      idVerifiedAt: NOW,
      helpedNeedCount: 100,
      fulfilledPostedCount: 100,
      approvedCertificateCount: 10,
      avgRating: 5,
      ratingCount: 100,
      activatedReferralCount: 10,
    }
    expect(earnedBadgeCount(everything)).toBe(TOTAL_BADGE_COUNT)
  })
})

describe('trust score', () => {
  it('weights sum to exactly 100, so a perfect score is reachable', () => {
    const total =
      TRUST_WEIGHTS.email +
      TRUST_WEIGHTS.face +
      TRUST_WEIGHTS.phone +
      TRUST_WEIGHTS.id +
      TRUST_WEIGHTS.certificateCap +
      TRUST_WEIGHTS.fulfilledCap +
      TRUST_WEIGHTS.reviewsMax +
      TRUST_WEIGHTS.badgeCap +
      TRUST_WEIGHTS.skillEndorsementCap
    expect(total).toBe(100)
  })

  it('a user who has done everything scores exactly 100', () => {
    expect(
      computeTrustScore({
        emailVerifiedAt: NOW,
        phoneVerifiedAt: NOW,
        faceVerifiedAt: NOW,
        idVerifiedAt: NOW,
        approvedCertificateCount: 10,
        fulfilledNeedCount: 100,
        avgRating: 5,
        ratingCount: 50,
        earnedBadgeCount: TOTAL_BADGE_COUNT,
        validatedSkillEndorsementCount: TRUST_WEIGHTS.skillEndorsementCap,
      }),
    ).toBe(100)
  })

  it('a brand new user scores 0', () => {
    expect(
      computeTrustScore({
        emailVerifiedAt: null,
        phoneVerifiedAt: null,
        faceVerifiedAt: null,
        idVerifiedAt: null,
        approvedCertificateCount: 0,
        fulfilledNeedCount: 0,
        avgRating: 0,
        ratingCount: 0,
        earnedBadgeCount: 0,
        validatedSkillEndorsementCount: 0,
      }),
    ).toBe(0)
  })

  it('more badges means more trust', () => {
    const base = {
      emailVerifiedAt: NOW,
      phoneVerifiedAt: null,
      faceVerifiedAt: null,
      idVerifiedAt: null,
      approvedCertificateCount: 0,
      fulfilledNeedCount: 0,
      avgRating: 0,
      ratingCount: 0,
      validatedSkillEndorsementCount: 0,
    }
    const none = computeTrustScore({ ...base, earnedBadgeCount: 0 })
    const some = computeTrustScore({ ...base, earnedBadgeCount: 3 })
    expect(some).toBeGreaterThan(none)
  })

  it('badge contribution is capped, so badges cannot dominate the score', () => {
    const base = {
      emailVerifiedAt: null,
      phoneVerifiedAt: null,
      faceVerifiedAt: null,
      idVerifiedAt: null,
      approvedCertificateCount: 0,
      fulfilledNeedCount: 0,
      avgRating: 0,
      ratingCount: 0,
      validatedSkillEndorsementCount: 0,
    }
    expect(computeTrustScore({ ...base, earnedBadgeCount: 999 }))
      .toBe(TRUST_WEIGHTS.badgeCap)
  })

  it('never exceeds 100', () => {
    expect(
      computeTrustScore({
        emailVerifiedAt: NOW,
        phoneVerifiedAt: NOW,
        faceVerifiedAt: NOW,
        idVerifiedAt: NOW,
        approvedCertificateCount: 999,
        fulfilledNeedCount: 999,
        avgRating: 5,
        ratingCount: 999,
        earnedBadgeCount: 999,
        validatedSkillEndorsementCount: 999,
      }),
    ).toBeLessThanOrEqual(100)
  })

  it('weights identity verification by how hard it is to fake', () => {
    // Phone (out-of-band OTP) > face (live selfie) > email (compulsory, free).
    expect(TRUST_WEIGHTS.phone).toBeGreaterThan(TRUST_WEIGHTS.face)
    expect(TRUST_WEIGHTS.face).toBeGreaterThan(TRUST_WEIGHTS.email)
  })
})
