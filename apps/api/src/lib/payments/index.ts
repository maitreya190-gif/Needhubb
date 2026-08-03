import { config } from '../../config'
import { manualProvider } from './manual'
import type { PaymentProvider } from './provider'

const providers: Record<string, PaymentProvider> = {
  manual: manualProvider,
}

/** Reads PAYMENT_PROVIDER at call time (not module load) so tests can swap it. */
export function getPaymentProvider(): PaymentProvider {
  return providers[config.paymentProvider] ?? manualProvider
}

export type { PaymentProvider, PaymentIntent, PaymentOutcome } from './provider'
