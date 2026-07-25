'use client'
import { useEffect, useState } from 'react'
import { api, type Report } from '@/lib/api'

type TargetTab = 'all' | 'USER' | 'NEED'
type StatusTab = 'OPEN' | 'RESOLVED'

const ACTIONS = [
  { value: 'dismiss',     label: 'Dismiss' },
  { value: 'warn_user',   label: 'Warn User' },
  { value: 'ban_user',    label: 'Ban User' },
  { value: 'remove_need', label: 'Remove Post' },
]

export default function ReportsPage() {
  const [targetTab, setTargetTab] = useState<TargetTab>('all')
  const [statusTab, setStatusTab] = useState<StatusTab>('OPEN')
  const [reports, setReports] = useState<Report[]>([])
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState('')
  const [acting, setActing] = useState<string | null>(null)

  async function load() {
    setLoading(true)
    setErr('')
    try {
      const params: { targetType?: string; status?: string } = { status: statusTab }
      if (targetTab !== 'all') params.targetType = targetTab
      setReports(await api.reports(params))
    } catch (e: any) {
      setErr(e.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [targetTab, statusTab])

  async function resolve(id: string, action: string) {
    setActing(id)
    try {
      await api.resolveReport(id, action)
      setReports(prev => prev.filter(r => r.id !== id))
    } catch (e: any) {
      alert(e.message)
    } finally {
      setActing(null)
    }
  }

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">Reports</h1>
        <span style={{ fontSize: 13, color: 'var(--muted)' }}>
          {!loading && `${reports.length} result${reports.length !== 1 ? 's' : ''}`}
        </span>
      </div>

      <div style={{ display: 'flex', gap: 12, marginBottom: 16, flexWrap: 'wrap' }}>
        <div className="tab-row" style={{ margin: 0 }}>
          {(['OPEN', 'RESOLVED'] as StatusTab[]).map(s => (
            <button key={s} className={`tab${statusTab === s ? ' active' : ''}`} onClick={() => setStatusTab(s)}>
              {s === 'OPEN' ? 'Open' : 'Resolved'}
            </button>
          ))}
        </div>
        <div className="tab-row" style={{ margin: 0 }}>
          {(['all', 'USER', 'NEED'] as TargetTab[]).map(t => (
            <button key={t} className={`tab${targetTab === t ? ' active' : ''}`} onClick={() => setTargetTab(t)}>
              {t === 'all' ? 'All' : t === 'USER' ? 'Users' : 'Posts'}
            </button>
          ))}
        </div>
      </div>

      {err && <p style={{ color: 'var(--clay)', fontWeight: 600, marginBottom: 16 }}>{err}</p>}

      <div className="card table-wrap">
        {loading ? (
          <div style={{ padding: '40px', textAlign: 'center', color: 'var(--muted)' }}>Loading…</div>
        ) : reports.length === 0 ? (
          <div style={{ padding: '40px', textAlign: 'center', color: 'var(--muted)' }}>No reports found.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Reporter</th>
                <th>Target</th>
                <th>Reason</th>
                <th>Date</th>
                <th>Status</th>
                {statusTab === 'OPEN' && <th>Resolve</th>}
              </tr>
            </thead>
            <tbody>
              {reports.map(r => (
                <ReportRow
                  key={r.id}
                  report={r}
                  open={statusTab === 'OPEN'}
                  acting={acting === r.id}
                  onResolve={(action) => resolve(r.id, action)}
                />
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}

function ReportRow({
  report, open, acting, onResolve,
}: {
  report: Report
  open: boolean
  acting: boolean
  onResolve: (action: string) => void
}) {
  const [action, setAction] = useState(ACTIONS[0].value)

  const badgeClass = report.status === 'OPEN'
    ? 'badge badge-open'
    : report.status === 'RESOLVED'
    ? 'badge badge-resolved'
    : 'badge badge-reviewed'

  return (
    <tr style={{ opacity: acting ? 0.5 : 1 }}>
      <td>
        <div style={{ fontWeight: 600, fontSize: 13.5 }}>{report.reporter.displayName}</div>
        <div style={{ fontSize: 12, color: 'var(--muted)', marginTop: 1 }}>{report.reporter.email}</div>
      </td>
      <td>
        <span className={report.targetType === 'USER' ? 'badge badge-connect' : 'badge badge-earn'}>
          {report.targetType}
        </span>
        <div style={{ fontSize: 11, color: 'var(--muted)', marginTop: 4, fontFamily: 'monospace' }}>
          {report.targetId.slice(0, 8)}…
        </div>
      </td>
      <td style={{ maxWidth: 240 }}>
        <span style={{ fontSize: 13, color: 'var(--ink)' }}>{report.reason}</span>
      </td>
      <td style={{ color: 'var(--muted)', fontSize: 13, whiteSpace: 'nowrap' }}>
        {new Date(report.createdAt).toLocaleDateString()}
      </td>
      <td>
        <span className={badgeClass}>{report.status}</span>
      </td>
      {open && (
        <td>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <select
              value={action}
              onChange={e => setAction(e.target.value)}
              style={{
                padding: '6px 10px', borderRadius: 8, border: '1.5px solid var(--rail)',
                background: 'var(--card)', fontSize: 12, color: 'var(--ink)', fontFamily: 'inherit',
              }}
            >
              {ACTIONS.map(a => (
                <option key={a.value} value={a.value}>{a.label}</option>
              ))}
            </select>
            <button
              className="btn btn-warn"
              style={{ fontSize: 12 }}
              disabled={acting}
              onClick={() => onResolve(action)}
            >
              Apply
            </button>
          </div>
        </td>
      )}
    </tr>
  )
}
