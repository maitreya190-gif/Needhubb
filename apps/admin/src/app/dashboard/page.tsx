'use client'
import { useEffect, useState } from 'react'
import { api, type Stats } from '@/lib/api'
import Link from 'next/link'

export default function DashboardPage() {
  const [stats, setStats] = useState<Stats | null>(null)
  const [err, setErr] = useState('')

  useEffect(() => {
    api.stats().then(setStats).catch(e => setErr(e.message))
  }, [])

  if (err) return <p style={{ color: 'var(--clay)', fontWeight: 600 }}>{err}</p>

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">Overview</h1>
        <span style={{ fontSize: 12, color: 'var(--muted)', fontWeight: 600 }}>
          {new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' })}
        </span>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 16, marginBottom: 32 }}>
        <StatCard label="Total Users" value={stats?.users} href="/dashboard/users" accent="var(--forest)" />
        <StatCard label="Total Needs" value={stats?.needs} href="/dashboard/needs" accent="var(--ochre)" />
        <StatCard label="Pending Certs" value={stats?.pendingCerts} href="/dashboard/certificates" accent="var(--clay)" />
        <StatCard label="Open Reports" value={stats?.openReports} href="/dashboard/reports" accent="var(--clay)" />
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
        <QuickLink
          href="/dashboard/certificates"
          icon="🎓"
          title="Certificate Queue"
          desc={stats ? `${stats.pendingCerts} awaiting review` : '—'}
          accent="var(--forest)"
        />
        <QuickLink
          href="/dashboard/reports"
          icon="🚩"
          title="Reports"
          desc={stats ? `${stats.openReports} open reports` : '—'}
          accent="var(--clay)"
        />
        <QuickLink
          href="/dashboard/users"
          icon="👥"
          title="User Management"
          desc="Search, view, and remove users"
          accent="var(--ochre)"
        />
        <QuickLink
          href="/dashboard/needs"
          icon="📋"
          title="Needs / Posts"
          desc="Review and moderate posted needs"
          accent="var(--forest)"
        />
      </div>
    </div>
  )
}

function StatCard({
  label, value, href, accent,
}: {
  label: string
  value: number | undefined
  href: string
  accent: string
}) {
  return (
    <Link href={href} style={{ textDecoration: 'none' }}>
      <div className="stat-card" style={{ cursor: 'pointer', transition: 'box-shadow .12s' }}
        onMouseEnter={e => (e.currentTarget.style.boxShadow = '0 4px 18px rgba(33,30,23,.09)')}
        onMouseLeave={e => (e.currentTarget.style.boxShadow = 'none')}
      >
        <div className="label">{label}</div>
        <div className="value" style={{ color: accent }}>
          {value ?? <span style={{ fontSize: 28, opacity: .4 }}>—</span>}
        </div>
      </div>
    </Link>
  )
}

function QuickLink({
  href, icon, title, desc, accent,
}: {
  href: string
  icon: string
  title: string
  desc: string
  accent: string
}) {
  return (
    <Link href={href} style={{ textDecoration: 'none' }}>
      <div className="card" style={{
        padding: '18px 20px',
        display: 'flex',
        alignItems: 'center',
        gap: 14,
        cursor: 'pointer',
        transition: 'box-shadow .12s',
      }}
        onMouseEnter={e => (e.currentTarget.style.boxShadow = '0 4px 18px rgba(33,30,23,.09)')}
        onMouseLeave={e => (e.currentTarget.style.boxShadow = 'none')}
      >
        <div style={{
          width: 44, height: 44, borderRadius: 13,
          background: `color-mix(in srgb, ${accent} 12%, transparent)`,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: 22, flexShrink: 0,
        }}>
          {icon}
        </div>
        <div>
          <div style={{ fontWeight: 700, fontSize: 15, marginBottom: 2 }}>{title}</div>
          <div style={{ fontSize: 12.5, color: 'var(--muted)' }}>{desc}</div>
        </div>
        <div style={{ marginLeft: 'auto', color: 'var(--muted)', fontSize: 18 }}>›</div>
      </div>
    </Link>
  )
}
