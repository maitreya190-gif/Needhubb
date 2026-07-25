'use client'
import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { setSecret, api } from '@/lib/api'

export default function LoginPage() {
  const [secret, setSecretVal] = useState('')
  const [err, setErr] = useState('')
  const [loading, setLoading] = useState(false)
  const router = useRouter()

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setErr('')
    setLoading(true)
    setSecret(secret)
    try {
      await api.stats()
      router.push('/dashboard')
    } catch {
      setErr('Invalid admin secret.')
      setLoading(false)
    }
  }

  return (
    <div style={{
      minHeight: '100vh',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      background: 'var(--paper)',
    }}>
      <div style={{
        width: 380,
        background: 'var(--card)',
        border: '1px solid var(--rail)',
        borderRadius: 20,
        padding: '36px 32px',
      }}>
        {/* Logo mark */}
        <div style={{ display: 'flex', gap: 0, marginBottom: 22 }}>
          <div style={{ width: 28, height: 28, borderRadius: 8, background: 'var(--forest)' }} />
          <div style={{ width: 28, height: 28, borderRadius: 8, background: 'var(--clay)', marginLeft: -10 }} />
        </div>

        <h1 style={{ fontSize: 24, fontWeight: 800, letterSpacing: '-.02em', marginBottom: 4 }}>
          NeedHub Admin
        </h1>
        <p style={{ color: 'var(--muted)', fontSize: 13, marginBottom: 28 }}>
          Enter the admin secret to continue.
        </p>

        <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
          <div>
            <label className="section-label" style={{ display: 'block', marginBottom: 6 }}>
              Admin Secret
            </label>
            <input
              className="input"
              type="password"
              placeholder="••••••••••••"
              value={secret}
              onChange={e => setSecretVal(e.target.value)}
              autoFocus
              required
            />
          </div>

          {err && (
            <p style={{ color: 'var(--clay)', fontSize: 13, fontWeight: 600 }}>{err}</p>
          )}

          <button
            className="btn btn-primary"
            type="submit"
            disabled={loading || !secret}
            style={{ marginTop: 4, justifyContent: 'center', padding: '12px 0' }}
          >
            {loading ? 'Verifying…' : 'Sign in →'}
          </button>
        </form>
      </div>
    </div>
  )
}
