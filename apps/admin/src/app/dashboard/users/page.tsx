'use client'
import { useEffect, useState, useCallback } from 'react'
import { api, type AdminUser } from '@/lib/api'

const PAGE_SIZE = 20

export default function UsersPage() {
  const [search, setSearch] = useState('')
  const [users, setUsers] = useState<AdminUser[]>([])
  const [skip, setSkip] = useState(0)
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState('')
  const [acting, setActing] = useState<string | null>(null)
  const [query, setQuery] = useState('')

  async function load(q: string, s: number, append = false) {
    setLoading(true)
    setErr('')
    try {
      const data = await api.users(q || undefined, s)
      setUsers(prev => append ? [...prev, ...data] : data)
    } catch (e: any) {
      setErr(e.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    setSkip(0)
    load(query, 0)
  }, [query])

  function handleSearch(e: React.FormEvent) {
    e.preventDefault()
    setQuery(search)
  }

  function loadMore() {
    const next = skip + PAGE_SIZE
    setSkip(next)
    load(query, next, true)
  }

  async function deleteUser(id: string, name: string) {
    if (!confirm(`Permanently delete "${name}"? This cannot be undone.`)) return
    setActing(id)
    try {
      await api.deleteUser(id)
      setUsers(prev => prev.filter(u => u.id !== id))
    } catch (e: any) {
      alert(e.message)
    } finally {
      setActing(null)
    }
  }

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">Users</h1>
        {!loading && (
          <span style={{ fontSize: 13, color: 'var(--muted)' }}>
            {users.length} loaded
          </span>
        )}
      </div>

      <form onSubmit={handleSearch} style={{ display: 'flex', gap: 10, marginBottom: 20 }}>
        <input
          className="input"
          placeholder="Search by name or email…"
          value={search}
          onChange={e => setSearch(e.target.value)}
          style={{ maxWidth: 340 }}
        />
        <button className="btn btn-ghost" type="submit">Search</button>
        {query && (
          <button
            className="btn btn-ghost"
            type="button"
            onClick={() => { setSearch(''); setQuery('') }}
          >
            Clear
          </button>
        )}
      </form>

      {err && <p style={{ color: 'var(--clay)', fontWeight: 600, marginBottom: 16 }}>{err}</p>}

      <div className="card table-wrap">
        {loading && users.length === 0 ? (
          <div style={{ padding: '40px', textAlign: 'center', color: 'var(--muted)' }}>Loading…</div>
        ) : users.length === 0 ? (
          <div style={{ padding: '40px', textAlign: 'center', color: 'var(--muted)' }}>No users found.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>User</th>
                <th>Verification</th>
                <th>Needs</th>
                <th>Reports</th>
                <th>Joined</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {users.map(u => (
                <tr key={u.id} style={{ opacity: acting === u.id ? 0.5 : 1 }}>
                  <td>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                      <div style={{
                        width: 34, height: 34, borderRadius: 10,
                        background: 'var(--forest)',
                        display: 'flex', alignItems: 'center', justifyContent: 'center',
                        color: '#fff', fontWeight: 800, fontSize: 13, flexShrink: 0,
                      }}>
                        {u.displayName.charAt(0).toUpperCase()}
                      </div>
                      <div>
                        <div style={{ fontWeight: 600, fontSize: 13.5 }}>{u.displayName}</div>
                        <div style={{ fontSize: 12, color: 'var(--muted)', marginTop: 1 }}>{u.email}</div>
                      </div>
                    </div>
                  </td>
                  <td>
                    <span className={
                      u.verificationLevel === 'VERIFIED'
                        ? 'badge badge-approved'
                        : u.verificationLevel === 'PENDING'
                        ? 'badge badge-pending'
                        : 'badge'
                    }
                      style={u.verificationLevel === 'UNVERIFIED'
                        ? { background: 'rgba(33,30,23,.07)', color: 'var(--muted)' }
                        : {}}
                    >
                      {u.verificationLevel}
                    </span>
                  </td>
                  <td style={{ fontSize: 13, color: 'var(--muted)' }}>{u._count.needs}</td>
                  <td>
                    <span style={{
                      fontSize: 13,
                      fontWeight: u._count.reports > 0 ? 700 : 400,
                      color: u._count.reports > 2 ? 'var(--clay)' : 'var(--muted)',
                    }}>
                      {u._count.reports}
                    </span>
                  </td>
                  <td style={{ color: 'var(--muted)', fontSize: 13, whiteSpace: 'nowrap' }}>
                    {new Date(u.createdAt).toLocaleDateString()}
                  </td>
                  <td>
                    <button
                      className="btn btn-danger"
                      style={{ fontSize: 12 }}
                      disabled={acting === u.id}
                      onClick={() => deleteUser(u.id, u.displayName)}
                    >
                      Delete
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {users.length > 0 && users.length % PAGE_SIZE === 0 && (
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
