/**
 * The active PaymentProvider today: no gateway, no credentials. The user is
 * redirected to a real `upi://pay` link against a fixed personal collection
 * VPA (config.plusUpiId) — this genuinely opens the PhonePe/Paytm/GPay/etc.
 * chooser on Android, no merchant account needed. Whether that self-reported
 * "it succeeded" is trusted immediately (with an admin-audit flag) or must
 * wait for admin confirmation is a product decision made in plus.router.ts,
 * not here — this provider only ever truthfully reports what IT can verify,
 * which for a bank-less manual flow is nothing. See provider.ts.
 */

import { config } from '../../config'
import type { PaymentProvider } from './provider'

/** Builds a real UPI Deep Linking Specification payment URI. */
export function buildUpiDeepLink(args: { amountPaise: number; currency: string; reference: string }): string {
  const amount = (args.amountPaise / 100).toFixed(2)
  const params = new URLSearchParams({
    pa: config.plusUpiId,
    pn: 'NeedHub',
    am: amount,
    cu: args.currency,
    tr: args.reference,
    tn: 'NeedHub Plus',
  })
  return `upi://pay?${params.toString()}`
}

export const manualProvider: PaymentProvider = {
  id: 'manual',

  async createIntent(args) {
    const upiDeepLink = buildUpiDeepLink({
      amountPaise: args.amountPaise,
      currency: args.currency,
      reference: args.idempotencyKey,
    })
    return {
      paymentId: '', // filled in by the caller once the PlusPayment row exists
      providerOrderId: null,
      amountPaise: args.amountPaise,
      currency: args.currency,
      action: 'manual_instructions',
      instructions: `Pay ₹${(args.amountPaise / 100).toFixed(2)} via UPI to ${config.plusUpiId}, then confirm in the app.`,
      upiDeepLink,
      checkoutPayload: null,
    }
  },

  // The manual provider can never self-verify a payment — it has no bank
  // connection at all. Whether "the user says it succeeded" is trusted is
  // decided explicitly in plus.router.ts, not here. This is the provider's
  // core honesty property and is asserted directly in
  // lib/payments/__tests__/manual.test.ts.
  async verifyClientConfirmation() {
    return { outcome: 'pending' }
  },

  // No webhook exists for a manual flow.
  handleWebhook: undefined,
}
