export type VerificationLevel = 'EMAIL' | 'PHONE' | 'ID'

export interface UserPublic {
  id: string
  displayName: string
  verificationLevel: VerificationLevel
  createdAt: string
}

export interface ProfilePublic {
  userId: string
  bio: string | null
  locationText: string | null
  pointsTotal: number
  skills: string[]
  interests: string[]
}
