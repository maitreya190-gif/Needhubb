/**
 * Earned badges — visible proof of what someone has actually done here.
 *
 * Every badge is *derived*, never granted. There is no badge table and nothing
 * to award manually: `computeBadges` is a pure function of facts already stored
 * (verification timestamps, fulfilled needs, reviews, certificates, referrals),
 * so a badge cannot exist unless the thing it claims is true. That also means
 * no schema migration and no backfill — badges work retroactively for every
 * user from the day this ships.
 *
 * This replaces a hardcoded list in the profile screen that showed every new
 * user three badges ("First Help", "5-Star", "Quick Reply") marked as earned
 * before they had done anything at all.
 *
 * Badges also feed the trust score — see `trust-score.ts`. Keep the two in
 * sync: BADGE_DEFINITIONS is the single source of truth for what exists.
 */

export interface BadgeInputs {
  emailVerifiedAt: Date | null
  phoneVerifiedAt: Date | null
  faceVerifiedAt: Date | null
  /** Needs where this user was the accepted responder and the need completed. */
  helpedNeedCount: number
  /** Needs this user posted that reached FULFILLED. */
  fulfilledPostedCount: number
  approvedCertificateCount: number
  avgRating: number // 0 when ratingCount is 0
  ratingCount: number
  activatedReferralCount: number
}

export interface Badge {
  /** Stable identifier — safe to persist or match on in the client. */
  id: string
  label: string
  /** One line explaining what it took, shown on locked badges as the goal. */
  description: string
  /** Groups badges in the UI. */
  group: 'verification' | 'helping' | 'quality' | 'community'
  earned: boolean
}

interface BadgeDefinition extends Omit<Badge, 'earned'> {
  isEarned: (i: BadgeInputs) => boolean
}

/**
 * Thresholds are deliberately reachable. A badge nobody can earn is decoration,
 * and the whole point of removing the fake ones was to stop decorating.
 */
export const BADGE_DEFINITIONS: BadgeDefinition[] = [
  // ── Verification: who you are ────────────────────────────────────────────
  {
    id: 'email_verified',
    label: 'Email Verified',
    description: 'Confirm your email address',
    group: 'verification',
    isEarned: (i) => i.emailVerifiedAt != null,
  },
  {
    id: 'phone_verified',
    label: 'Phone Verified',
    description: 'Verify a real phone number by OTP',
    group: 'verification',
    isEarned: (i) => i.phoneVerifiedAt != null,
  },
  {
    id: 'face_verified',
    label: 'Face Verified',
    description: 'Pass a live selfie check',
    group: 'verification',
    isEarned: (i) => i.faceVerifiedAt != null,
  },
  {
    id: 'fully_verified',
    label: 'Fully Verified',
    description: 'Verify email, phone and face',
    group: 'verification',
    isEarned: (i) =>
      i.emailVerifiedAt != null && i.phoneVerifiedAt != null && i.faceVerifiedAt != null,
  },

  // ── Helping: what you have actually done for people ──────────────────────
  {
    id: 'first_help',
    label: 'First Help',
    description: 'Complete your first need for someone',
    group: 'helping',
    isEarned: (i) => i.helpedNeedCount >= 1,
  },
  {
    id: 'helping_hand',
    label: 'Helping Hand',
    description: 'Complete 5 needs for others',
    group: 'helping',
    isEarned: (i) => i.helpedNeedCount >= 5,
  },
  {
    id: 'reliable',
    label: 'Reliable',
    description: 'Complete 10 needs for others',
    group: 'helping',
    isEarned: (i) => i.helpedNeedCount >= 10,
  },
  {
    id: 'veteran',
    label: 'Veteran',
    description: 'Complete 25 needs for others',
    group: 'helping',
    isEarned: (i) => i.helpedNeedCount >= 25,
  },
  {
    id: 'follows_through',
    label: 'Follows Through',
    description: 'Have 5 needs you posted reach completion',
    group: 'helping',
    isEarned: (i) => i.fulfilledPostedCount >= 5,
  },

  // ── Quality: what other people say about you ─────────────────────────────
  {
    id: 'five_star',
    label: '5-Star',
    description: 'Hold a 4.8+ rating across at least 5 reviews',
    group: 'quality',
    // Requires a real sample — one glowing review is not a 5-star record.
    isEarned: (i) => i.ratingCount >= 5 && i.avgRating >= 4.8,
  },
  {
    id: 'well_reviewed',
    label: 'Well Reviewed',
    description: 'Receive 10 reviews',
    group: 'quality',
    isEarned: (i) => i.ratingCount >= 10,
  },

  // ── Community: credentials and growing the place ─────────────────────────
  {
    id: 'certified',
    label: 'Certified',
    description: 'Get a certificate approved',
    group: 'community',
    isEarned: (i) => i.approvedCertificateCount >= 1,
  },
  {
    id: 'community_builder',
    label: 'Community Builder',
    description: 'Refer 3 people who join and get active',
    group: 'community',
    isEarned: (i) => i.activatedReferralCount >= 3,
  },
]

/**
 * Every badge with its earned state, in definition order.
 *
 * Returns locked badges too — seeing what is still available is the point, and
 * it is what makes the row honest: an unearned badge is visibly unearned rather
 * than quietly omitted.
 */
export function computeBadges(inputs: BadgeInputs): Badge[] {
  return BADGE_DEFINITIONS.map(({ isEarned, ...rest }) => ({
    ...rest,
    earned: isEarned(inputs),
  }))
}

/** How many badges this user has actually earned. Feeds the trust score. */
export function earnedBadgeCount(inputs: BadgeInputs): number {
  return BADGE_DEFINITIONS.reduce((n, d) => n + (d.isEarned(inputs) ? 1 : 0), 0)
}

export const TOTAL_BADGE_COUNT = BADGE_DEFINITIONS.length
