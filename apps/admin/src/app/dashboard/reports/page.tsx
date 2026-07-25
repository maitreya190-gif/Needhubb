'use client'
import { useEffect, useState } from 'react'
import { api, type Report, type ContextMessage } from '@/lib/api'

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
  const [showContext, setShowContext] = useState(false)

  const badgeClass = report.status === 'OPEN'
    ? 'badge badge-open'
    : report.status === 'RESOLVED'
    ? 'badge badge-resolved'
    : 'badge badge-reviewed'

  const hasContext = report.target?.kind === 'MESSAGE' &&
    report.target.contextMessages && report.target.contextMessages.length > 0

  return (
    <>
      <tr style={{ opacity: acting ? 0.5 : 1 }}>
        <td>
          <div style={{ fontWeight: 600, fontSize: 13.5 }}>{report.reporter.displayName}</div>
          <div style={{ fontSize: 12, color: 'var(--muted)', marginTop: 1 }}>{report.reporter.email}</div>
        </td>
        <td>
          <span className={report.targetType === 'USER' ? 'badge badge-connect' : 'badge badge-earn'}>
            {report.targetType}
          </span>
          {report.target?.kind === 'NEED' && report.target.title && (
            <div style={{ fontSize: 11, color: 'var(--ink)', marginTop: 4, maxWidth: 160 }}>
              {report.target.title}
            </div>
          )}
          {report.target?.kind === 'MESSAGE' && report.target.senderName && (
            <div style={{ fontSize: 11, color: 'var(--muted)', marginTop: 4 }}>
              from {report.target.senderName}
            </div>
          )}
          {!report.target && (
            <div style={{ fontSize: 11, color: 'var(--muted)', marginTop: 4, fontFamily: 'monospace' }}>
              {report.targetId.slice(0, 8)}…
            </div>
          )}
        </td>
        <td style={{ maxWidth: 240 }}>
          <span style={{ fontSize: 13, color: 'var(--ink)' }}>{report.reason}</span>
          {report.target?.kind === 'MESSAGE' && report.target.body && (
            <div style={{
              marginTop: 6, padding: '6px 10px', background: 'var(--paper)',
              borderRadius: 8, fontSize: 12, color: 'var(--muted)',
              border: '1px solid var(--rail)', fontStyle: 'italic',
            }}>
              "{report.target.body.slice(0, 120)}{report.target.body.length > 120 ? '…' : ''}"
            </div>
          )}
          {hasContext && (
            <button
              onClick={() => setShowContext(v => !v)}
              style={{
                marginTop: 6, fontSize: 11, color: 'var(--accent)',
                background: 'none', border: 'none', cursor: 'pointer', padding: 0,
              }}
            >
              {showContext ? '▲ Hide' : '▼ Show'} chat context ({report.target!.contextMessages!.length} msgs)
            </button>
          )}
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
      {showContext && hasContext && (
        <tr>
          <td colSpan={open ? 6 : 5} style={{ padding: '0 16px 16px' }}>
            <ChatContextPanel messages={report.target!.contextMessages!} flaggedId={report.targetId} />
          </td>
        </tr>
      )}
    </>
  )
}

function ChatContextPanel({ messages, flaggedId }: { messages: ContextMessage[]; flaggedId: string }) {
  return (
    <div style={{
      background: 'var(--paper)', border: '1.5px solid var(--rail)',
      borderRadius: 12, padding: '12px 14px', maxHeight: 320, overflowY: 'auto',
    }}>
      <div style={{ fontSize: 11, fontWeight: 700, color: 'var(--muted)', marginBottom: 10, letterSpacing: '0.5px' }}>
        CHAT CONTEXT (last {messages.length} messages)
      </div>
      {messages.map(m => (
        <div
          key={m.id}
          style={{
            marginBottom: 8, padding: '8px 10px', borderRadius: 8,
            background: m.id === flaggedId ? 'rgba(239,68,68,0.1)' : 'var(--card)',
            border: m.id === flaggedId ? '1.5px solid rgba(239,68,68,0.4)' : '1px solid var(--rail)',
          }}
        >
          <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 3 }}>
            <span style={{ fontSize: 12, fontWeight: 600, color: 'var(--ink)' }}>{m.sender.displayName}</span>
            <span style={{ fontSize: 11, color: 'var(--muted)' }}>
              {new Date(m.createdAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
            </span>
          </div>
          <span style={{ fontSize: 13, color: m.id === flaggedId ? '#dc2626' : 'var(--ink)' }}>{m.body}</span>
          {m.id === flaggedId && (
            <span style={{ marginLeft: 8, fontSize: 10, fontWeight: 700, color: '#dc2626' }}>← FLAGGED</span>
          )}
        </div>
      ))}
    </div>
  )
}
