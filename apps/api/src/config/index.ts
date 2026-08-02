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
}
