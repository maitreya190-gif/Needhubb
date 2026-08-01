/**
 * A user's on-platform track record — the counts that badges and the trust
 * score are both derived from.
 *
 * Lives here rather than in a router because three different endpoints need
 * the same numbers (own profile, someone else's profile, the feed), and they
 * must agree: a badge shown on a profile has to reflect the same facts the
 * trust score was calculated from.
 *
 * The plural form batches with `groupBy` so the feed stays one round of
 * queries rather than one per poster.
 */

import { prisma } from './prisma'
import type { BadgeInputs } from './badges'

export interface TrackRecord {
  approvedCertificateCount: number
  /** Needs this user posted that reached FULFILLED. */
  fulfilledPostedCount: number
  /** Needs this user was the accepted responder on, which then completed. */
  helpedNeedCount: number
  avgRating: number
  ratingCount: number
  activatedReferralCount: number
}

const EMPTY: TrackRecord = {
  approvedCertificateCount: 0,
  fulfilledPostedCount: 0,
  helpedNeedCount: 0,
  avgRating: 0,
  ratingCount: 0,
  activatedReferralCount: 0,
}

/** Track records for many users, in one batched round of queries. */
export async function fetchTrackRecords(
  userIds: string[],
): Promise<Map<string, TrackRecord>> {
  const out = new Map<string, TrackRecord>()
  if (userIds.length === 0) return out

  const [certs, posted, helped, reviews, referrals] = await Promise.all([
    prisma.certificate.groupBy({
      by: ['userId'],
      where: { userId: { in: userIds }, status: 'APPROVED' },
      _count: { id: true },
    }),
    prisma.need.groupBy({
      by: ['posterId'],
      where: { posterId: { in: userIds }, status: 'FULFILLED' },
      _count: { id: true },
    }),
    // Helping is an accepted response on a need that then completed — being
    // picked is not the same as having delivered.
    prisma.interestResponse.groupBy({
      by: ['responderId'],
      where: {
        responderId: { in: userIds },
        status: 'ACCEPTED',
        need: { status: 'FULFILLED' },
      },
      _count: { id: true },
    }),
    prisma.review.groupBy({
      by: ['revieweeId'],
      where: { revieweeId: { in: userIds } },
      _avg: { rating: true },
      _count: { id: true },
    }),
    prisma.referral.groupBy({
      by: ['referrerId'],
      where: { referrerId: { in: userIds }, status: 'ACTIVATED' },
      _count: { id: true },
    }),
  ])

  const certBy = new Map(certs.map((g) => [g.userId, g._count.id]))
  const postedBy = new Map(posted.map((g) => [g.posterId, g._count.id]))
  const helpedBy = new Map(helped.map((g) => [g.responderId, g._count.id]))
  const reviewBy = new Map(
    reviews.map((g) => [g.revieweeId, { avg: g._avg.rating ?? 0, count: g._count.id }]),
  )
  const referralBy = new Map(referrals.map((g) => [g.referrerId, g._count.id]))

  for (const id of userIds) {
    const review = reviewBy.get(id)
    out.set(id, {
      approvedCertificateCount: certBy.get(id) ?? 0,
      fulfilledPostedCount: postedBy.get(id) ?? 0,
      helpedNeedCount: helpedBy.get(id) ?? 0,
      avgRating: review ? Math.round(review.avg * 10) / 10 : 0,
      ratingCount: review?.count ?? 0,
      activatedReferralCount: referralBy.get(id) ?? 0,
    })
  }
  return out
}

/** Track record for a single user. */
export async function fetchTrackRecord(userId: string): Promise<TrackRecord> {
  const records = await fetchTrackRecords([userId])
  return records.get(userId) ?? EMPTY
}

export interface VerificationTimestamps {
  emailVerifiedAt: Date | null
  phoneVerifiedAt: Date | null
  faceVerifiedAt: Date | null
}

/** Combine identity verification with track record into badge inputs. */
export function toBadgeInputs(
  verification: VerificationTimestamps,
  record: TrackRecord,
): BadgeInputs {
  return { ...verification, ...record }
}

/**
 * Completed needs for the trust score: helping someone else and following
 * through on your own posted need both count as a real completed outcome.
 */
export function totalFulfilledCount(record: TrackRecord): number {
  return record.helpedNeedCount + record.fulfilledPostedCount
}
