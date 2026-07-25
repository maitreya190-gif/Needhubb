export type NeedType = 'EARN' | 'CONNECT'
export type NeedStatus = 'OPEN' | 'IN_PROGRESS' | 'FULFILLED' | 'CLOSED'
export type EarnCategory = 'TUTORING' | 'FREELANCE' | 'GOODS_BUY' | 'GOODS_SELL' | 'REPAIR' | 'OTHER'
export type ConnectCategory = 'STUDY_PARTNER' | 'ACTIVITY_PARTNER' | 'HOBBY' | 'MENTOR' | 'OTHER'

export interface NeedPublic {
  id: string
  posterId: string
  title: string
  description: string
  needType: NeedType
  earnCategory: EarnCategory | null
  connectCategory: ConnectCategory | null
  isPaid: boolean
  budgetMin: number | null
  budgetMax: number | null
  deadline: string | null
  locationText: string | null
  status: NeedStatus
  parentNeedId: string | null
  createdAt: string
}

export interface DecomposedNeed {
  title: string
  description: string
  needType: NeedType
  earnCategory: EarnCategory | null
  connectCategory: ConnectCategory | null
  budgetMin: number | null
  budgetMax: number | null
  deadline: string | null
}

export interface DecomposeResult {
  needs: DecomposedNeed[]
}
