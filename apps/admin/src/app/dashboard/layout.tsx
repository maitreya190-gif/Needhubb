'use client'
import { useEffect } from 'react'
import { useRouter, usePathname } from 'next/navigation'
import Link from 'next/link'
import { getSecret, clearSecret } from '@/lib/api'

const NAV = [
  { href: '/dashboard',              label: 'Overview',     icon: '⬡' },
  { href: '/dashboard/certificates', label: 'Certificates', icon: '🎓' },
  { href: '/dashboard/reports',      label: 'Reports',      icon: '🚩' },
  { href: '/dashboard/users',        label: 'Users',        icon: '👥' },
  { href: '/dashboard/needs',        label: 'Needs',        icon: '📋' },
]

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter()
  const pathname = usePathname()

  useEffect(() => {
    if (!getSecret()) router.replace('/login')
  }, [router])

  function signOut() {
    clearSecret()
    router.push('/login')
  }

  return (
    <div style={{ display: 'flex', minHeight: '100vh' }}>
      {/* Sidebar */}
      <aside style={{
        width: 'var(--sidebar-w)',
        flexShrink: 0,
        background: 'var(--card)',
        borderRight: '1px solid var(--rail)',
        display: 'flex',
        flexDirection: 'column',
        padding: '24px 0 16px',
        position: 'fixed',
        top: 0, bottom: 0, left: 0,
        zIndex: 10,
      }}>
        {/* Logo */}
        <div style={{ padding: '0 20px 24px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <div style={{ display: 'flex' }}>
              <div style={{ width: 22, height: 22, borderRadius: 6, background: 'var(--forest)' }} />
              <div style={{ width: 22, height: 22, borderRadius: 6, background: 'var(--clay)', marginLeft: -8 }} />
            </div>
            <span style={{ fontWeight: 800, fontSize: 15, letterSpacing: '-.01em' }}>Admin</span>
          </div>
        </div>

        {/* Nav */}
        <nav style={{ flex: 1, padding: '0 10px' }}>
          {NAV.map(item => {
            const active = item.href === '/dashboard'
              ? pathname === '/dashboard'
              : pathname.startsWith(item.href)
            return (
              <Link key={item.href} href={item.href} style={{
                display: 'flex',
                alignItems: 'center',
                gap: 10,
                padding: '9px 12px',
                borderRadius: 11,
                marginBottom: 2,
                fontWeight: active ? 700 : 500,
                fontSize: 14,
                color: active ? 'var(--ink)' : 'var(--muted)',
                background: active ? 'rgba(33,30,23,.07)' : 'transparent',
                transition: 'all .1s',
              }}>
                <span style={{ fontSize: 15 }}>{item.icon}</span>
                {item.label}
              </Link>
            )
          })}
        </nav>

        {/* Sign out */}
        <div style={{ padding: '0 10px' }}>
          <button
            onClick={signOut}
            style={{
              display: 'flex', alignItems: 'center', gap: 8,
              width: '100%', padding: '9px 12px', borderRadius: 11,
              background: 'none', border: 'none',
              fontSize: 13, fontWeight: 600, color: 'var(--clay)',
            }}
          >
            ← Sign out
          </button>
        </div>
      </aside>

      {/* Main content */}
      <main style={{
        marginLeft: 'var(--sidebar-w)',
        flex: 1,
        padding: '32px 36px',
        minHeight: '100vh',
      }}>
        {children}
      </main>
    </div>
  )
}
