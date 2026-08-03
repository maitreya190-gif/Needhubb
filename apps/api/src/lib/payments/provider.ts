/**
 * NeedHub Plus payments go through this interface, never through a hardcoded
 * gateway call. No payment gateway exists anywhere in this codebase today,
 * and no merchant credentials are available — so the active implementation
 * (manual.ts) is a manual/admin-confirm flow: the user pays by UPI outside
 * the app, submits a reference, and an admin marks it paid in the portal.
 *
 * Dropping in a real gateway (Razorpay, etc.) later is exactly one new file
 * implementing this interface, plus flipping the PAYMENT_PROVIDER env var —
 * nothing else in the codebase changes, because every call site only ever
 * calls getPaymentProvider().
 */

export type PaymentOutcome = 'paid' | 'pending' | 'failed'

export interface PaymentIntent {
  /** Our PlusPayment.id — always present, the one thing every provider shares. */
  paymentId: string
  providerOrderId: string | null
  amountPaise: number
  currency: string
  /** Tells the client what to render: plain instructions, or a checkout SDK. */
  action: 'manual_instructions' | 'checkout'
  /** UPI id / QR payload text, manual provider only. */
  instructions?: string | null
  /**
   * A real `upi://pay?...` deep link, manual provider only — opening it on
   * Android launches the native "complete with PhonePe/Paytm/GPay/etc."
   * chooser against the configured collection VPA. Null for providers that
   * use a checkout SDK instead.
   */
  upiDeepLink?: string | null
  /** Gateway SDK options, checkout providers only. */
  checkoutPayload?: Record<string, unknown> | null
}

export interface PaymentProvider {
  readonly id: string

  createIntent(args: {
    userId: string
    amountPaise: number
    currency: string
    idempotencyKey: string
  }): Promise<PaymentIntent>

  /**
   * Called when the client believes payment happened. The manual provider
   * ALWAYS returns 'pending' here — only an admin marking it paid in the
   * portal can ever move a manual payment to PAID. A real gateway provider
   * would verify a signature/order status and may return 'paid' directly.
   */
  verifyClientConfirmation(args: {
    payment: { id: string; providerOrderId: string | null }
    clientPayload: Record<string, unknown>
  }): Promise<{ outcome: PaymentOutcome; providerPaymentId?: string; raw?: unknown }>

  /** Manual provider has no webhook — returns null. */
  handleWebhook?(
    rawBody: Buffer,
    headers: Record<string, string | string[] | undefined>,
  ): Promise<{ providerPaymentId: string; providerOrderId: string; outcome: PaymentOutcome; raw: unknown } | null>
}
