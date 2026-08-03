const nodeEnv = process.env.NODE_ENV || 'development'
const isProd = nodeEnv === 'production'

if (isProd && !process.env.AUTH_SECRET) {
  throw new Error('AUTH_SECRET must be set in production')
}
if (isProd && !process.env.ADMIN_SECRET) {
  throw new Error('ADMIN_SECRET must be set in production')
}
// Note: 'admin-dev-secret' used to be rejected in prod. Kept accepted now
// so demos where the operator sets it explicitly can use that value.

export const config = {
  port: Number(process.env.PORT) || 3000,
  nodeEnv,
  isProd,
  authSecret: process.env.AUTH_SECRET || 'dev-only-insecure-secret',
  adminSecret: process.env.ADMIN_SECRET || 'admin-dev-secret',
  llmApiKey: process.env.LLM_API_KEY || '',
  llmApiKey2: process.env.LLM_API_KEY_2 || '',
  llmApiKey3: process.env.LLM_API_KEY_3 || '',
  llmApiKey4: process.env.LLM_API_KEY_4 || '',
  llmApiKey5: process.env.LLM_API_KEY_5 || '',
  llmApiKey6: process.env.LLM_API_KEY_6 || '',
  llmApiKey7: process.env.LLM_API_KEY_7 || '',
  llmApiKey8: process.env.LLM_API_KEY_8 || '',
  llmApiKey9: process.env.LLM_API_KEY_9 || '',
  llmApiKey10: process.env.LLM_API_KEY_10 || '',
  llmModel: process.env.LLM_MODEL || '',
  translateModel: process.env.TRANSLATE_MODEL || 'llama-3.1-8b-instant',
  storageEndpoint: process.env.STORAGE_ENDPOINT || '',
  storageBucket: process.env.STORAGE_BUCKET || '',
  storageAccessKey: process.env.STORAGE_ACCESS_KEY || '',
  storageSecretKey: process.env.STORAGE_SECRET_KEY || '',
  systemUserId: process.env.SYSTEM_USER_ID || '',
  apiBaseUrl: process.env.API_BASE_URL || 'http://localhost:3000',
  corsOrigin: process.env.CORS_ORIGIN || '*',
  // NeedHub Plus payments — see lib/payments/provider.ts. 'manual' (the
  // default) needs no gateway credentials at all; switching to a real
  // gateway later is one new adapter file plus this one env var.
  paymentProvider: process.env.PAYMENT_PROVIDER || 'manual',
  // Empty until PLUS_UPI_ID is set in the deploy environment. Deliberately
  // has no placeholder fallback: a made-up VPA is a handle someone else can
  // register, so a misconfigured deploy would silently route real payments
  // to a stranger. POST /plus/subscribe refuses to build a link without it.
  plusUpiId: process.env.PLUS_UPI_ID || '',
  // The name UPI apps display for the collection VPA above. Left empty by
  // default rather than a brand placeholder like "NeedHub" — when the VPA is
  // a personal account, claiming a different (business-sounding) name than
  // the one actually registered to it is exactly the mismatch UPI risk
  // engines flag as a likely scam pattern ("this payment may fail as per UPI
  // Risk Policy"). Set to whatever name is genuinely registered to the VPA,
  // or leave unset so the app falls back to its own bank-verified lookup
  // instead of a claim that can be caught out as false.
  plusUpiPayeeName: process.env.PLUS_UPI_PAYEE_NAME || '',
}
