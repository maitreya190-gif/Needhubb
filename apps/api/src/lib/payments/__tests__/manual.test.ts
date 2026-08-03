import { describe, it, expect } from 'vitest'
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
    const link = buildUpiDeepLink({ amountPaise: 5000, currency: 'INR', reference: 'ref-123' })
    const url = new URL(link.replace('upi://', 'https://'))
    expect(url.searchParams.get('am')).toBe('50.00')
    expect(url.searchParams.get('cu')).toBe('INR')
    expect(url.searchParams.get('tr')).toBe('ref-123')
    expect(url.searchParams.get('pa')).toBeTruthy()
  })

  it('never produces a fractional-paise amount', () => {
    const link = buildUpiDeepLink({ amountPaise: 5099, currency: 'INR', reference: 'r' })
    const url = new URL(link.replace('upi://', 'https://'))
    expect(url.searchParams.get('am')).toBe('50.99')
  })
})

describe('getPaymentProvider', () => {
  it('defaults to the manual provider', () => {
    expect(getPaymentProvider().id).toBe('manual')
  })
})
