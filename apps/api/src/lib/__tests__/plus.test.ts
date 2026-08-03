import { describe, it, expect, vi, beforeEach } from 'vitest'

const mocks = vi.hoisted(() => ({
  plusSubscriptionFindMany: vi.fn(),
  plusSubscriptionFindUnique: vi.fn(),
  plusSubscriptionUpdateMany: vi.fn(),
  plusSubscriptionUpsert: vi.fn(),
  plusPaymentUpdateMany: vi.fn(),
  plusPaymentUpdate: vi.fn(),
}))

vi.mock('../prisma', () => ({
  prisma: {
    plusSubscription: {
      findMany: mocks.plusSubscriptionFindMany,
      findUnique: mocks.plusSubscriptionFindUnique,
      updateMany: mocks.plusSubscriptionUpdateMany,
      upsert: mocks.plusSubscriptionUpsert,
    },
    plusPayment: {
      updateMany: mocks.plusPaymentUpdateMany,
      update: mocks.plusPaymentUpdate,
    },
  },
}))

import {
  isPlusActive, expirePlusIfNeeded, fetchPlusUserIds, activatePlus, PLUS_PERIOD_DAYS,
  canSelfReportInstantly, SELF_REPORT_RENEWAL_WINDOW_MS,
} from '../plus'

beforeEach(() => {
  Object.values(mocks).forEach((m) => m.mockReset())
})

describe('isPlusActive', () => {
  const now = new Date('2026-06-15T00:00:00Z')

  it('is false for null/undefined', () => {
    expect(isPlusActive(null, now)).toBe(false)
    expect(isPlusActive(undefined, now)).toBe(false)
  })

  it('is false when status is not ACTIVE, even with a future period end', () => {
    expect(isPlusActive({ status: 'PENDING', currentPeriodEnd: new Date('2026-07-01') }, now)).toBe(false)
    expect(isPlusActive({ status: 'CANCELED', currentPeriodEnd: new Date('2026-07-01') }, now)).toBe(false)
    expect(isPlusActive({ status: 'EXPIRED', currentPeriodEnd: new Date('2026-07-01') }, now)).toBe(false)
  })

  it('is false when ACTIVE but currentPeriodEnd is null', () => {
    expect(isPlusActive({ status: 'ACTIVE', currentPeriodEnd: null }, now)).toBe(false)
  })

  it('is false when ACTIVE but the period has already ended — status alone is never trusted', () => {
    expect(isPlusActive({ status: 'ACTIVE', currentPeriodEnd: new Date('2026-06-01') }, now)).toBe(false)
  })

  it('is true only when ACTIVE AND the period has not ended', () => {
    expect(isPlusActive({ status: 'ACTIVE', currentPeriodEnd: new Date('2026-07-01') }, now)).toBe(true)
  })
})

describe('expirePlusIfNeeded', () => {
  it('does nothing when not ACTIVE', async () => {
    await expirePlusIfNeeded({ userId: 'u1', status: 'PENDING', currentPeriodEnd: null })
    expect(mocks.plusSubscriptionUpdateMany).not.toHaveBeenCalled()
  })

  it('does nothing when ACTIVE but not yet expired', async () => {
    const now = new Date('2026-06-15T00:00:00Z')
    await expirePlusIfNeeded({ userId: 'u1', status: 'ACTIVE', currentPeriodEnd: new Date('2026-07-01') }, now)
    expect(mocks.plusSubscriptionUpdateMany).not.toHaveBeenCalled()
  })

  it('flips to EXPIRED once the period has passed', async () => {
    const now = new Date('2026-06-15T00:00:00Z')
    mocks.plusSubscriptionUpdateMany.mockResolvedValue({ count: 1 })
    await expirePlusIfNeeded({ userId: 'u1', status: 'ACTIVE', currentPeriodEnd: new Date('2026-06-01') }, now)
    expect(mocks.plusSubscriptionUpdateMany).toHaveBeenCalledWith({
      where: { userId: 'u1', status: 'ACTIVE' },
      data: { status: 'EXPIRED' },
    })
  })

  it('never throws even if the write fails', async () => {
    const now = new Date('2026-06-15T00:00:00Z')
    mocks.plusSubscriptionUpdateMany.mockRejectedValue(new Error('db down'))
    await expect(
      expirePlusIfNeeded({ userId: 'u1', status: 'ACTIVE', currentPeriodEnd: new Date('2026-06-01') }, now),
    ).resolves.toBeUndefined()
  })
})

describe('fetchPlusUserIds', () => {
  it('returns an empty set without querying when given no ids', async () => {
    expect(await fetchPlusUserIds([])).toEqual(new Set())
    expect(mocks.plusSubscriptionFindMany).not.toHaveBeenCalled()
  })

  it('filters on BOTH status ACTIVE and an unexpired period, never status alone', async () => {
    mocks.plusSubscriptionFindMany.mockResolvedValue([{ userId: 'u1' }])
    const result = await fetchPlusUserIds(['u1', 'u2'])
    expect(result).toEqual(new Set(['u1']))
    const where = mocks.plusSubscriptionFindMany.mock.calls[0][0].where
    expect(where.status).toBe('ACTIVE')
    expect(where.userId.in).toEqual(['u1', 'u2'])
    expect(where.currentPeriodEnd.gt).toBeInstanceOf(Date)
  })

  it('fails safe to an empty set on a DB error, never throws', async () => {
    mocks.plusSubscriptionFindMany.mockRejectedValue(new Error('db down'))
    expect(await fetchPlusUserIds(['u1'])).toEqual(new Set())
  })
})

describe('activatePlus', () => {
  function fakeTx() {
    return {
      plusPayment: { updateMany: mocks.plusPaymentUpdateMany, update: mocks.plusPaymentUpdate },
      plusSubscription: { findUnique: mocks.plusSubscriptionFindUnique, upsert: mocks.plusSubscriptionUpsert },
    } as any
  }

  it('is a no-op if the payment was already PAID (idempotency guard)', async () => {
    mocks.plusPaymentUpdateMany.mockResolvedValue({ count: 0 })
    const result = await activatePlus(fakeTx(), { userId: 'u1', paymentId: 'p1' })
    expect(result.activated).toBe(false)
    expect(mocks.plusSubscriptionUpsert).not.toHaveBeenCalled()
  })

  it('starts a fresh PLUS_PERIOD_DAYS period from now on first-ever activation', async () => {
    mocks.plusPaymentUpdateMany.mockResolvedValue({ count: 1 })
    mocks.plusSubscriptionFindUnique.mockResolvedValue(null)
    mocks.plusSubscriptionUpsert.mockResolvedValue({})
    mocks.plusPaymentUpdate.mockResolvedValue({})

    const before = Date.now()
    const result = await activatePlus(fakeTx(), { userId: 'u1', paymentId: 'p1' })
    expect(result.activated).toBe(true)

    const upsertArgs = mocks.plusSubscriptionUpsert.mock.calls[0][0]
    const periodEnd: Date = upsertArgs.create.currentPeriodEnd
    const expectedMs = before + PLUS_PERIOD_DAYS * 24 * 3_600_000
    expect(Math.abs(periodEnd.getTime() - expectedMs)).toBeLessThan(5000)
  })

  it('stacks on top of an existing unexpired period rather than truncating it', async () => {
    const farFuture = new Date(Date.now() + 20 * 24 * 3_600_000)
    mocks.plusPaymentUpdateMany.mockResolvedValue({ count: 1 })
    mocks.plusSubscriptionFindUnique.mockResolvedValue({
      currentPeriodStart: new Date(), currentPeriodEnd: farFuture,
    })
    mocks.plusSubscriptionUpsert.mockResolvedValue({})
    mocks.plusPaymentUpdate.mockResolvedValue({})

    await activatePlus(fakeTx(), { userId: 'u1', paymentId: 'p1' })
    const upsertArgs = mocks.plusSubscriptionUpsert.mock.calls[0][0]
    const periodEnd: Date = upsertArgs.update.currentPeriodEnd
    const expectedMs = farFuture.getTime() + PLUS_PERIOD_DAYS * 24 * 3_600_000
    expect(periodEnd.getTime()).toBe(expectedMs)
  })

  it('starts a fresh period from now when renewing after the previous one already lapsed', async () => {
    const pastEnd = new Date(Date.now() - 5 * 24 * 3_600_000)
    mocks.plusPaymentUpdateMany.mockResolvedValue({ count: 1 })
    mocks.plusSubscriptionFindUnique.mockResolvedValue({
      currentPeriodStart: new Date(Date.now() - 35 * 24 * 3_600_000), currentPeriodEnd: pastEnd,
    })
    mocks.plusSubscriptionUpsert.mockResolvedValue({})
    mocks.plusPaymentUpdate.mockResolvedValue({})

    const before = Date.now()
    await activatePlus(fakeTx(), { userId: 'u1', paymentId: 'p1' })
    const upsertArgs = mocks.plusSubscriptionUpsert.mock.calls[0][0]
    const periodEnd: Date = upsertArgs.update.currentPeriodEnd
    const expectedMs = before + PLUS_PERIOD_DAYS * 24 * 3_600_000
    expect(Math.abs(periodEnd.getTime() - expectedMs)).toBeLessThan(5000)
  })
})

describe('canSelfReportInstantly — closes the free-infinite-renewal loop', () => {
  const now = new Date('2026-06-15T00:00:00Z')

  it('allows it when there is no subscription yet (first-ever activation)', () => {
    expect(canSelfReportInstantly(null, now)).toBe(true)
  })

  it('allows it when the existing subscription is not active (PENDING/EXPIRED/CANCELED)', () => {
    expect(canSelfReportInstantly({ status: 'EXPIRED', currentPeriodEnd: new Date('2026-06-01') }, now)).toBe(true)
  })

  it('BLOCKS it when comfortably active — this is the exploit-closing case', () => {
    const farFuture = new Date(now.getTime() + 20 * 24 * 3_600_000) // 20 days left
    expect(canSelfReportInstantly({ status: 'ACTIVE', currentPeriodEnd: farFuture }, now)).toBe(false)
  })

  it('allows it again once within the renewal window near expiry', () => {
    const almostDone = new Date(now.getTime() + 1 * 24 * 3_600_000) // 1 day left
    expect(canSelfReportInstantly({ status: 'ACTIVE', currentPeriodEnd: almostDone }, now)).toBe(true)
  })

  it('is exactly inclusive at the renewal window boundary', () => {
    const atBoundary = new Date(now.getTime() + SELF_REPORT_RENEWAL_WINDOW_MS)
    expect(canSelfReportInstantly({ status: 'ACTIVE', currentPeriodEnd: atBoundary }, now)).toBe(true)
    const justPastBoundary = new Date(now.getTime() + SELF_REPORT_RENEWAL_WINDOW_MS + 1)
    expect(canSelfReportInstantly({ status: 'ACTIVE', currentPeriodEnd: justPastBoundary }, now)).toBe(false)
  })

  it('the exploit scenario: repeated self-report while active is blocked every time until near expiry', () => {
    // Simulates a scripted attacker: subscribe -> self-report -> repeat.
    // First call (no subscription) succeeds; every immediate repeat while
    // the resulting 30-day period is still far from over is blocked.
    let sub: { status: 'ACTIVE'; currentPeriodEnd: Date } | null = null
    expect(canSelfReportInstantly(sub, now)).toBe(true)
    sub = { status: 'ACTIVE', currentPeriodEnd: new Date(now.getTime() + PLUS_PERIOD_DAYS * 24 * 3_600_000) }
    for (let i = 0; i < 5; i++) {
      expect(canSelfReportInstantly(sub, now)).toBe(false)
    }
  })
})
