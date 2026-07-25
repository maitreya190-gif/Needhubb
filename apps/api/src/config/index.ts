export const config = {
  port: Number(process.env.PORT) || 3000,
  nodeEnv: process.env.NODE_ENV || 'development',
  authSecret: process.env.AUTH_SECRET || '',
  adminSecret: process.env.ADMIN_SECRET || 'admin-dev-secret',
  llmApiKey: process.env.LLM_API_KEY || '',
  llmModel: process.env.LLM_MODEL || '',
  storageEndpoint: process.env.STORAGE_ENDPOINT || '',
  storageBucket: process.env.STORAGE_BUCKET || '',
  storageAccessKey: process.env.STORAGE_ACCESS_KEY || '',
  storageSecretKey: process.env.STORAGE_SECRET_KEY || '',
  // Reporter id for auto-generated moderation reports. If unset, we lazily create
  // a "system" user on demand — see lib/system-user.ts.
  systemUserId: process.env.SYSTEM_USER_ID || '',
  apiBaseUrl: process.env.API_BASE_URL || 'http://localhost:3000',
}
