const API_BASE = process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:3000'

export function getSecret(): string {
  if (typeof window === 'undefined') return ''
  return localStorage.getItem('nh_admin_secret') ?? ''
}

export function setSecret(s: string) {
  localStorage.setItem('nh_admin_secret', s)
}

export function clearSecret() {
  localStorage.removeItem('nh_admin_secret')
}

async function req<T>(
  method: string,
  path: string,
  body?: unknown,
): Promise<T> {
  const res = await fetch(`${API_BASE}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      'x-admin-secret': getSecret(),
    },
    body: body ? JSON.stringify(body) : undefined,
  })
  if (!res.ok) {
    const err = await res.json().catch(() => ({}))
    throw new Error((err as any).error ?? `HTTP ${res.status}`)
  }
  return res.json() as Promise<T>
}

export const api = {
  stats: () => req<Stats>('GET', '/admin/stats'),

  certificates: (status = 'PENDING_REVIEW') =>
    req<Cert[]>('GET', `/admin/certificates?status=${status}`),
  reviewCert: (id: string, status: 'APPROVED' | 'REJECTED', pointsAwarded?: number) =>
    req('PATCH', `/admin/certificates/${id}`, { status, pointsAwarded }),

  reports: (params?: { targetType?: string; status?: string }) => {
    const qs = new URLSearchParams()
    if (params?.targetType) qs.set('targetType', params.targetType)
    if (params?.status) qs.set('status', params.status)
    return req<Report[]>('GET', `/admin/reports?${qs}`)
  },
  resolveReport: (id: string, action: string) =>
    req('PATCH', `/admin/reports/${id}/resolve`, { action }),

  users: (search?: string, skip = 0) => {
    const qs = new URLSearchParams({ skip: String(skip) })
    if (search) qs.set('search', search)
    return req<AdminUser[]>('GET', `/admin/users?${qs}`)
  },
  deleteUser: (id: string) => req('DELETE', `/admin/users/${id}`),

  needs: (status?: string, skip = 0) => {
    const qs = new URLSearchParams({ skip: String(skip) })
    if (status) qs.set('status', status)
    return req<AdminNeed[]>('GET', `/admin/needs?${qs}`)
  },
  deleteNeed: (id: string) => req('DELETE', `/admin/needs/${id}`),
}

// ── Types ────────────────────────────────────────────────────────────────────

export interface Stats {
  users: number
  needs: number
  pendingCerts: number
  openReports: number
}

export interface Cert {
  id: string
  type: string
  fileUrl: string
  status: string
  pointsAwarded: number | null
  createdAt: string
  user: { id: string; username: string | null; displayName: string; email: string }
}

export interface ContextMessage {
  id: string
  body: string
  imageUrl: string | null
  createdAt: string
  sender: { id: string; username: string | null; displayName: string }
}

export interface ReportTarget {
  kind: 'USER' | 'NEED' | 'MESSAGE'
  // USER
  displayName?: string
  email?: string
  // NEED
  title?: string
  description?: string
  needType?: string
  posterName?: string
  pending?: boolean
  blockedText?: string | null
  // MESSAGE
  body?: string
  senderName?: string
  contextMessages?: ContextMessage[]
}

export interface Report {
  id: string
  targetType: string
  targetId: string
  reason: string
  status: string
  createdAt: string
  reporter: { id: string; username: string | null; displayName: string; email: string }
  target?: ReportTarget | null
}

export interface AdminUser {
  id: string
  username: string | null
  displayName: string
  email: string
  verificationLevel: string
  createdAt: string
  _count: { needs: number; reports: number }
}

export interface AdminNeed {
  id: string
  title: string
  status: string
  needType: string
  createdAt: string
  poster: { id: string; username: string | null; displayName: string; email: string }
}
