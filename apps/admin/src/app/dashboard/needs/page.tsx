'use client'
import { useEffect, useState } from 'react'
import { api, type AdminNeed } from '@/lib/api'

type StatusTab = 'all' | 'OPEN' | 'CLOSED' | 'FULFILLED'

const PAGE_SIZE = 20

export default function NeedsPage() {
  const [statusTab, setStatusTab] = useState<StatusTab>('all')
  const [needs, setNeeds] = useState<AdminNeed[]>([])
  const [skip, setSkip] = useState(0)
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState('')
  const [acting, setActing] = useState<string | null>(null)

  async function load(status: StatusTab, s: number, append = false) {
    setLoading(true)
    setErr('')
    try {
      const data = await api.needs(status === 'all' ? undefined : status, s)
      setNeeds(prev => append ? [...prev, ...data] : data)
    } catch (e: any) {
      setErr(e.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    setSkip(0)
    load(statusTab, 0)
  }, [statusTab])

  function loadMore() {
    const next = skip + PAGE_SIZE
    setSkip(next)
    load(statusTab, next, true)
  }

  async function deleteNeed(id: string, title: string) {
    if (!confirm(`Delete "${title}"? This cannot be undone.`)) return
    setActing(id)
    try {
      await api.deleteNeed(id)
      setNeeds(prev => prev.filter(n => n.id !== id))
    } catch (e: any) {
      alert(e.message)
    } finally {
      setActing(null)
    }
  }

  const NEED_TYPE_COLORS: Record<string, string> = {
    EARN: 'var(--ochre)',
    CONNECT: 'var(--forest)',
  }

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">Needs</h1>
        {!loading && (
          <span style={{ fontSize: 13, color: 'var(--muted)' }}>
            {needs.length} loaded
          </span>
        )}
      </div>

      <div className="tab-row">
        {(['all', 'OPEN', 'CLOSED', 'FULFILLED'] as StatusTab[]).map(t => (
          <button key={t} className={`tab${statusTab === t ? ' active' : ''}`} onClick={() => setStatusTab(t)}>
            {t === 'all' ? 'All' : t.charAt(0) + t.slice(1).toLowerCase()}
          </button>
        ))}
      </div>

      {err && <p style={{ color: 'var(--clay)', fontWeight: 600, marginBottom: 16 }}>{err}</p>}

      <div className="card table-wrap">
        {loading && needs.length === 0 ? (
          <div style={{ padding: '40px', textAlign: 'center', color: 'var(--muted)' }}>Loading…</div>
        ) : needs.length === 0 ? (
          <div style={{ padding: '40px', textAlign: 'center', color: 'var(--muted)' }}>No needs found.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Title</th>
                <th>Type</th>
                <th>Posted by</th>
                <th>Status</th>
                <th>Date</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {needs.map(n => {
                const typeColor = NEED_TYPE_COLORS[n.needType] ?? 'var(--muted)'
                const badgeClass = n.status === 'OPEN'
                  ? 'badge badge-open'
                  : n.status === 'FULFILLED'
                  ? 'badge badge-approved'
                  : 'badge badge-reviewed'

                return (
                  <tr key={n.id} style={{ opacity: acting === n.id ? 0.5 : 1 }}>
                    <td style={{ maxWidth: 280 }}>
                      <div style={{ fontWeight: 600, fontSize: 13.5, lineHeight: 1.3 }}>{n.title}</div>
                      <div style={{ fontSize: 11, color: 'var(--muted)', marginTop: 2, fontFamily: 'monospace' }}>
                        {n.id.slice(0, 8)}…
                      </div>
                    </td>
                    <td>
                      <span style={{
                        display: 'inline-flex', alignItems: 'center',
                        padding: '2px 8px', borderRadius: 6,
                        fontSize: 11, fontWeight: 700, letterSpacing: '.03em', textTransform: 'uppercase',
                        background: `color-mix(in srgb, ${typeColor} 12%, transparent)`,
                        color: typeColor,
                      }}>
                        {n.needType}
                      </span>
                    </td>
                    <td>
                      <div style={{ fontWeight: 600, fontSize: 13 }}>{n.poster.displayName}</div>
                      <div style={{ fontSize: 12, color: 'var(--muted)', marginTop: 1 }}>{n.poster.email}</div>
                    </td>
                    <td>
                      <span className={badgeClass}>{n.status}</span>
                    </td>
                    <td style={{ color: 'var(--muted)', fontSize: 13, whiteSpace: 'nowrap' }}>
                      {new Date(n.createdAt).toLocaleDateString()}
                    </td>
                    <td>
                      <button
                        className="btn btn-danger"
                        style={{ fontSize: 12 }}
                        disabled={acting === n.id}
                        onClick={() => deleteNeed(n.id, n.title)}
                      >
                        Delete
                      </button>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        )}
      </div>

      {needs.length > 0 && needs.length % PAGE_SIZE === 0 && (
        <div style={{ textAlign: 'center', marginTop: 16 }}>
          <button
            className="btn btn-ghost"
            onClick={loadMore}
            disabled={loading}
          >
            {loading ? 'Loading…' : 'Load more'}
          </button>
        </div>
      )}
    </div>
  )
}
