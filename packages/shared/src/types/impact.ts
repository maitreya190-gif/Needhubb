export type CertificateType = 'NSS' | 'TREE_PLANTATION' | 'CLEANUP' | 'VOLUNTEERING' | 'OTHER'
export type AchievementCategory = 'COMPETITION' | 'HACKATHON' | 'TOURNAMENT' | 'AWARD' | 'OTHER'
export type ReviewStatus = 'PENDING_REVIEW' | 'APPROVED' | 'REJECTED'

export interface CertificatePublic {
  id: string
  type: CertificateType
  status: ReviewStatus
  pointsAwarded: number | null
  createdAt: string
}

export interface AchievementPublic {
  id: string
  title: string
  description: string | null
  category: AchievementCategory
  status: ReviewStatus
  createdAt: string
}

export interface PointsLedgerEntry {
  id: string
  delta: number
  reason: string
  refId: string | null
  createdAt: string
}
