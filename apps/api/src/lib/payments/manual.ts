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
  // NPCI mandates the tr (transaction reference) be alphanumeric only, max 35
  // chars, and requires PSPs to reject anything else. A raw crypto.randomUUID()
  // is 36 chars and contains hyphens — non-compliant on both counts, and a
  // real cause of UPI apps failing with "could not initiate transaction"
  // before the request ever reaches the payer's bank. Sanitize rather than
  // pass the idempotency key through untouched.
  const tr = args.reference.replace(/[^a-zA-Z0-9]/g, '').slice(0, 35)
  const params = new URLSearchParams({
    pa: config.plusUpiId,
    am: amount,
    cu: args.currency,
    tr,
    tn: 'NeedHub Plus',
  })
  // pn (payee name) is only included when it's genuinely configured to match
  // the account. Claiming "NeedHub" for what is, today, a personal VPA is a
  // real name/account mismatch — UPI apps cross-check pn against the actual
  // registered name and surface a fraud-risk warning when they disagree.
  // Omitting it lets the UPI app show its own verified lookup instead.
  if (config.plusUpiPayeeName.trim()) {
    params.set('pn', config.plusUpiPayeeName.trim())
  }
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
      // Never echoes config.plusUpiId here — every subscriber would see the
      // raw personal VPA in plain text on this screen otherwise. The deep
      // link itself still routes to it (a UPI app necessarily shows the
      // payee during the actual payment step, same as any UPI transaction),
      // but there's no reason to additionally broadcast it in our own UI.
      instructions: `Pay ₹${(args.amountPaise / 100).toFixed(2)} via UPI, then confirm in the app.`,
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
