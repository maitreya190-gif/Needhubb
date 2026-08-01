import 'dotenv/config'
import { defineConfig } from 'prisma/config'

export default defineConfig({
  schema: 'prisma/schema.prisma',
  migrations: {
    path: 'prisma/migrations',
  },
  datasource: {
    // Prefer DIRECT_URL (non-pooled) for CLI operations — Neon's pgbouncer
    // pooler runs in transaction mode which can't hold session-level advisory
    // locks that prisma migrate/db push need. Falls back to DATABASE_URL.
    url: process.env.DIRECT_URL || process.env.DATABASE_URL!,
  },
})
