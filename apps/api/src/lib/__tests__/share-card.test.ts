/**
 * Sharing turns a Need into a public, unauthenticated URL, so the two things
 * worth pinning hardest are: (1) only genuinely live, public Needs are
 * shareable, and (2) the payload never carries private or internal fields —
 * a regression in either is a data leak, not a cosmetic bug.
 */

import { describe, it, expect, vi, beforeEach } from 'vitest'

const mocks = vi.hoisted(() => ({ needFindUnique: vi.fn() }))

vi.mock('../prisma', () => ({
  prisma: { need: { findUnique: mocks.needFindUnique } },
}))

import {
  isShareable, buildShareCard, fetchShareableNeed, renderSharePage,
  escapeHtml, needDeepLink, needShareUrl, SHAREABLE_STATUSES,
} from '../share-card'

const BASE = 'https://needhub.example'

function needRow(overrides: Record<string, unknown> = {}) {
  return {
    id: 'need-1',
    title: 'Need a Flutter tutor',
    description: 'Looking for help with state management this weekend.',
    needType: 'EARN',
    earnCategory: 'TUTORING',
    connectCategory: null,
    isPaid: true,
    budgetMin: 500,
    budgetMax: 900,
    locationText: 'Koramangala',
    status: 'OPEN',
    isUrgent: false,
    deadline: null,
    poster: { displayName: 'Aarav', profile: { avatarUrl: 'https://cdn/a.png' } },
    ...overrides,
  } as any
}

beforeEach(() => {
  Object.values(mocks).forEach((m) => m.mockReset())
})

describe('isShareable — requirement: never share private/expired/closed needs', () => {
  it('allows the statuses that are genuinely public and live', () => {
    for (const status of SHAREABLE_STATUSES) {
      expect(isShareable(needRow({ status }))).toBe(true)
    }
  })

  it.each(['FULFILLED', 'CLOSED', 'EXPIRED'])('blocks %s needs', (status) => {
    expect(isShareable(needRow({ status }))).toBe(false)
  })

  it('blocks an urgent need whose deadline has already passed', () => {
    const need = needRow({ isUrgent: true, deadline: new Date('2020-01-01T00:00:00Z') })
    expect(isShareable(need, new Date('2026-01-01T00:00:00Z'))).toBe(false)
  })

  it('still allows an urgent need whose deadline is in the future', () => {
    const need = needRow({ isUrgent: true, deadline: new Date('2030-01-01T00:00:00Z') })
    expect(isShareable(need, new Date('2026-01-01T00:00:00Z'))).toBe(true)
  })

  it('ignores a stale deadline on a need that is not urgent', () => {
    const need = needRow({ isUrgent: false, deadline: new Date('2020-01-01T00:00:00Z') })
    expect(isShareable(need, new Date('2026-01-01T00:00:00Z'))).toBe(true)
  })
})

describe('buildShareCard — payload is an allowlist', () => {
  it('never carries coordinates, internal urgency fields or poster ids', () => {
    // Simulate the row accidentally arriving with private columns attached.
    const leaky = needRow({
      lat: 12.93, lng: 77.62, posterId: 'user-secret',
      urgencyConfidence: 0.91, renewalGeneration: 3,
    })
    const card = buildShareCard(leaky, BASE)
    const serialized = JSON.stringify(card)

    for (const forbidden of ['lat', 'lng', 'posterId', 'urgencyConfidence', 'renewalGeneration']) {
      expect(card).not.toHaveProperty(forbidden)
    }
    expect(serialized).not.toContain('user-secret')
    expect(serialized).not.toContain('12.93')
    expect(serialized).not.toContain('0.91')
  })

  it('exposes only the poster display name and avatar', () => {
    const card = buildShareCard(needRow(), BASE)
    expect(Object.keys(card.poster).sort()).toEqual(['avatarUrl', 'displayName'])
  })

  it('formats a budget range, a single value, and open-ended bounds', () => {
    expect(buildShareCard(needRow(), BASE).budget).toBe('₹500–₹900')
    expect(buildShareCard(needRow({ budgetMin: 700, budgetMax: 700 }), BASE).budget).toBe('₹700')
    expect(buildShareCard(needRow({ budgetMin: null }), BASE).budget).toBe('Up to ₹900')
    expect(buildShareCard(needRow({ budgetMax: null }), BASE).budget).toBe('From ₹500')
  })

  it('reports no budget for an unpaid need', () => {
    expect(buildShareCard(needRow({ isPaid: false }), BASE).budget).toBeNull()
  })

  it('humanises the category from the enum columns', () => {
    expect(buildShareCard(needRow(), BASE).category).toBe('Tutoring')
    const connect = needRow({
      needType: 'CONNECT', earnCategory: null, connectCategory: 'STUDY_PARTNER',
    })
    expect(buildShareCard(connect, BASE).category).toBe('Study Partner')
  })

  it('falls back to the need type when no category is set', () => {
    expect(buildShareCard(needRow({ earnCategory: null }), BASE).category).toBe('Earn')
  })

  it('truncates a long description instead of dumping the whole body', () => {
    const card = buildShareCard(needRow({ description: 'x'.repeat(400) }), BASE)
    expect(card.description.length).toBeLessThanOrEqual(180)
    expect(card.description.endsWith('…')).toBe(true)
  })

  it('only reports an expiry for urgent needs', () => {
    expect(buildShareCard(needRow({ deadline: new Date('2030-01-01') }), BASE).expiresAt).toBeNull()
    const urgent = needRow({ isUrgent: true, deadline: new Date('2030-01-01T00:00:00Z') })
    expect(buildShareCard(urgent, BASE).expiresAt).toBe('2030-01-01T00:00:00.000Z')
  })

  it('builds the share URL and deep link from the need id', () => {
    const card = buildShareCard(needRow(), BASE)
    expect(card.shareUrl).toBe(`${BASE}/n/need-1`)
    expect(card.deepLink).toBe('needhub:///need/need-1')
  })

  it('does not double up slashes when the base URL has a trailing one', () => {
    expect(needShareUrl('https://needhub.example/', 'abc')).toBe('https://needhub.example/n/abc')
  })
})

describe('fetchShareableNeed', () => {
  it('returns null for a need that does not exist', async () => {
    mocks.needFindUnique.mockResolvedValue(null)
    expect(await fetchShareableNeed('missing')).toBeNull()
  })

  it('returns null for an ineligible need rather than leaking it', async () => {
    mocks.needFindUnique.mockResolvedValue(needRow({ status: 'CLOSED' }))
    expect(await fetchShareableNeed('need-1')).toBeNull()
  })

  it('never selects private columns from the database at all', async () => {
    mocks.needFindUnique.mockResolvedValue(needRow())
    await fetchShareableNeed('need-1')
    const select = mocks.needFindUnique.mock.calls[0][0].select
    for (const forbidden of ['lat', 'lng', 'posterId', 'urgencyConfidence', 'renewalGeneration']) {
      expect(select).not.toHaveProperty(forbidden)
    }
  })

  it('fails safe to null on a DB error instead of throwing', async () => {
    mocks.needFindUnique.mockRejectedValue(new Error('db down'))
    expect(await fetchShareableNeed('need-1')).toBeNull()
  })
})

describe('renderSharePage', () => {
  it('escapes user-controlled text so a crafted title cannot inject markup', () => {
    const card = buildShareCard(
      needRow({
        title: '<script>alert(1)</script>',
        description: 'safe " quote \' test',
        poster: { displayName: '<img src=x onerror=1>', profile: null },
      }),
      BASE,
    )
    const html = renderSharePage(card)
    expect(html).not.toContain('<script>alert(1)</script>')
    expect(html).not.toContain('<img src=x onerror=1>')
    expect(html).toContain('&lt;script&gt;')
  })

  it('includes OpenGraph tags so links render a rich preview', () => {
    const html = renderSharePage(buildShareCard(needRow(), BASE))
    expect(html).toContain('property="og:title"')
    expect(html).toContain('property="og:description"')
    expect(html).toContain('name="twitter:card"')
  })

  it('offers both the deep link and the install fallback', () => {
    const html = renderSharePage(buildShareCard(needRow(), BASE))
    expect(html).toContain('needhub:///need/need-1')
    expect(html).toContain('play.google.com/store/apps/details?id=com.needhub.needhub')
  })

  it('escapeHtml covers every character that could break out of an attribute', () => {
    expect(escapeHtml(`<>&"'`)).toBe('&lt;&gt;&amp;&quot;&#39;')
  })
})

describe('needDeepLink', () => {
  it('uses the custom scheme the Android manifest registers', () => {
    expect(needDeepLink('abc123')).toBe('needhub:///need/abc123')
  })
})
