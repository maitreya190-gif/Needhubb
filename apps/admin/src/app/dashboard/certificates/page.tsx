'use client'
import { useEffect, useState } from 'react'
import { api, type Cert } from '@/lib/api'

type Tab = 'PENDING_REVIEW' | 'APPROVED' | 'REJECTED'

export default function CertificatesPage() {
  const [tab, setTab] = useState<Tab>('PENDING_REVIEW')
  const [certs, setCerts] = useState<Cert[]>([])
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState('')
  const [acting, setActing] = useState<string | null>(null)

  async function load(status: Tab) {
    setLoading(true)
    setErr('')
    try {
      setCerts(await api.certificates(status))
    } catch (e: any) {
      setErr(e.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load(tab) }, [tab])

  async function review(id: string, status: 'APPROVED' | 'REJECTED', pts?: number) {
    setActing(id)
    try {
      await api.reviewCert(id, status, pts)
      setCerts(prev => prev.filter(c => c.id !== id))
    } catch (e: any) {
      alert(e.message)
    } finally {
      setActing(null)
    }
  }

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">Certificates</h1>
        <span style={{ fontSize: 13, color: 'var(--muted)' }}>
          {!loading && `${certs.length} ${tab.toLowerCase().replace('_', ' ')}`}
        </span>
      </div>

      <div className="tab-row">
        {(['PENDING_REVIEW', 'APPROVED', 'REJECTED'] as Tab[]).map(t => (
          <button key={t} className={`tab${tab === t ? ' active' : ''}`} onClick={() => setTab(t)}>
            {t === 'PENDING_REVIEW' ? 'Pending' : t === 'APPROVED' ? 'Approved' : 'Rejected'}
          </button>
        ))}
      </div>

      {err && <p style={{ color: 'var(--clay)', fontWeight: 600, marginBottom: 16 }}>{err}</p>}

      <div className="card table-wrap">
        {loading ? (
          <div style={{ padding: '40px', textAlign: 'center', color: 'var(--muted)' }}>Loading…</div>
        ) : certs.length === 0 ? (
          <div style={{ padding: '40px', textAlign: 'center', color: 'var(--muted)' }}>No certificates found.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>User</th>
                <th>Type</th>
                <th>Submitted</th>
                <th>Points</th>
                <th>Status</th>
                {tab === 'PENDING_REVIEW' && <th>Actions</th>}
              </tr>
            </thead>
            <tbody>
              {certs.map(cert => (
                <CertRow
                  key={cert.id}
                  cert={cert}
                  pending={tab === 'PENDING_REVIEW'}
                  acting={acting === cert.id}
                  onApprove={pts => review(cert.id, 'APPROVED', pts)}
                  onReject={() => review(cert.id, 'REJECTED')}
                />
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}

function CertRow({
  cert, pending, acting, onApprove, onReject,
}: {
  cert: Cert
  pending: boolean
  acting: boolean
  onApprove: (pts: number) => void
  onReject: () => void
}) {
  const [pts, setPts] = useState('50')

  const badgeClass = cert.status === 'APPROVED'
    ? 'badge badge-approved'
    : cert.status === 'REJECTED'
    ? 'badge badge-rejected'
    : 'badge badge-pending'

  return (
    <tr style={{ opacity: acting ? 0.5 : 1 }}>
      <td>
        <div style={{ fontWeight: 600, fontSize: 13.5 }}>@{cert.user.username ?? cert.user.displayName}</div>
        <div style={{ fontSize: 12, color: 'var(--muted)', marginTop: 1 }}>{cert.user.email}</div>
      </td>
      <td>
        <span style={{ fontWeight: 600, fontSize: 13 }}>{cert.type.replace(/_/g, ' ')}</span>
      </td>
      <td style={{ color: 'var(--muted)', fontSize: 13 }}>
        {new Date(cert.createdAt).toLocaleDateString()}
      </td>
      <td style={{ fontSize: 13, color: 'var(--muted)' }}>
        {cert.pointsAwarded ?? '—'}
      </td>
      <td>
        <span className={badgeClass}>{cert.status.replace('_', ' ')}</span>
      </td>
      {pending && (
        <td>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <a
              href={cert.fileUrl}
              target="_blank"
              rel="noreferrer"
              className="btn btn-ghost"
              style={{ fontSize: 12 }}
            >
              View
            </a>
            <input
              type="number"
              value={pts}
              onChange={e => setPts(e.target.value)}
              style={{
                width: 60, padding: '6px 8px', borderRadius: 8,
                border: '1.5px solid var(--rail)', background: 'var(--card)',
                fontSize: 12, textAlign: 'center', color: 'var(--ink)',
              }}
              min="0"
              max="500"
            />
            <button
              className="btn btn-primary"
              style={{ fontSize: 12 }}
              disabled={acting}
              onClick={() => onApprove(Number(pts))}
            >
              Approve
            </button>
            <button
              className="btn btn-danger"
              style={{ fontSize: 12 }}
              disabled={acting}
              onClick={onReject}
            >
              Reject
            </button>
          </div>
        </td>
      )}
    </tr>
  )
}
