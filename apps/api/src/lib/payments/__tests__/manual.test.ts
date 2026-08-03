import { describe, it, expect, vi } from 'vitest'

// config reads PLUS_UPI_ID once at module load and has no fallback VPA on
// purpose, so this has to be set before the import graph evaluates.
vi.hoisted(() => {
  process.env.PLUS_UPI_ID = 'test-vpa@bank'
})

import { manualProvider, buildUpiDeepLink } from '../manual'
import { getPaymentProvider } from '../index'

describe('manualProvider.verifyClientConfirmation — the core honesty property', () => {
  it('NEVER returns paid — the manual provider genuinely cannot verify a bank transfer', async () => {
    const result = await manualProvider.verifyClientConfirmation({
      payment: { id: 'p1', providerOrderId: null },
      clientPayload: { anything: 'the client could claim here', selfReportedSuccess: true },
    })
    expect(result.outcome).toBe('pending')
  })

  it('has no webhook handler — there is no bank connection to receive one from', () => {
    expect(manualProvider.handleWebhook).toBeUndefined()
  })
})

describe('manualProvider.createIntent', () => {
  it('returns manual instructions and a real upi:// deep link', async () => {
    const intent = await manualProvider.createIntent({
      userId: 'u1', amountPaise: 5000, currency: 'INR', idempotencyKey: 'idem-1',
    })
    expect(intent.action).toBe('manual_instructions')
    expect(intent.upiDeepLink).toMatch(/^upi:\/\/pay\?/)
    expect(intent.amountPaise).toBe(5000)
  })
})

describe('buildUpiDeepLink', () => {
  it('encodes a real UPI Deep Linking Specification URI', () => {
    const link = buildUpiDeepLink({ amountPaise: 5000, currency: 'INR', reference: 'ref123' })
    const url = new URL(link.replace('upi://', 'https://'))
    expect(url.searchParams.get('am')).toBe('50.00')
    expect(url.searchParams.get('cu')).toBe('INR')
    expect(url.searchParams.get('tr')).toBe('ref123')
    expect(url.searchParams.get('pa')).toBe('test-vpa@bank')
  })

  it('never produces a fractional-paise amount', () => {
    const link = buildUpiDeepLink({ amountPaise: 5099, currency: 'INR', reference: 'r' })
    const url = new URL(link.replace('upi://', 'https://'))
    expect(url.searchParams.get('am')).toBe('50.99')
  })

  // NPCI mandates tr be alphanumeric-only, max 35 chars, and requires PSPs to
  // reject anything else — confirmed the real cause of a "could not initiate
  // transaction" failure in production, since crypto.randomUUID() (the actual
  // idempotencyKey used as the reference) is 36 chars and hyphenated.
  it('strips a hyphenated UUID reference down to a compliant alphanumeric tr', () => {
    const link = buildUpiDeepLink({
      amountPaise: 5000, currency: 'INR', reference: 'e3446fb5-abb0-40b1-92f4-3e6586fccfa8',
    })
    const url = new URL(link.replace('upi://', 'https://'))
    const tr = url.searchParams.get('tr')!
    expect(tr).toBe('e3446fb5abb040b192f43e6586fccfa8')
    expect(tr.length).toBeLessThanOrEqual(35)
    expect(tr).toMatch(/^[a-zA-Z0-9]+$/)
  })

  it('truncates any reference over 35 characters', () => {
    const link = buildUpiDeepLink({
      amountPaise: 5000, currency: 'INR', reference: 'a'.repeat(50),
    })
    const url = new URL(link.replace('upi://', 'https://'))
    expect(url.searchParams.get('tr')!.length).toBe(35)
  })

  // pn (payee name) mismatches against the real bank-registered name are
  // exactly what triggered a live "this payment may fail as per UPI Risk
  // Policy" warning in production — the VPA is a personal account, and we
  // were claiming a business name ("NeedHub") that doesn't match it.
  it('omits pn entirely when PLUS_UPI_PAYEE_NAME is not configured, rather than claiming a mismatched name', () => {
    const link = buildUpiDeepLink({ amountPaise: 5000, currency: 'INR', reference: 'ref123' })
    const url = new URL(link.replace('upi://', 'https://'))
    expect(url.searchParams.has('pn')).toBe(false)
  })

  it('includes pn only when explicitly configured to match the real account', async () => {
    vi.resetModules()
    process.env.PLUS_UPI_PAYEE_NAME = 'Real Account Holder Name'
    const { buildUpiDeepLink: buildWithName } = await import('../manual')
    const link = buildWithName({ amountPaise: 5000, currency: 'INR', reference: 'ref123' })
    const url = new URL(link.replace('upi://', 'https://'))
    expect(url.searchParams.get('pn')).toBe('Real Account Holder Name')
    delete process.env.PLUS_UPI_PAYEE_NAME
    vi.resetModules()
  })
})

describe('getPaymentProvider', () => {
  it('defaults to the manual provider', () => {
    expect(getPaymentProvider().id).toBe('manual')
  })
})
