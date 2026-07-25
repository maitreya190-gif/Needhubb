# NeedHub

Location-aware, needs-first marketplace for Earn, Connect, and Impact. See [Needhub.txt](Needhub.txt) for the full spec.

## Stack

- **Mobile**: Flutter (Android first, iOS via Codemagic later)
- **API**: Node.js + TypeScript (Express), Prisma 7 with Neon HTTP adapter
- **DB**: Neon Postgres (serverless)
- **Auth**: Clerk
- **AI**: Grok API (server-side only)
- **Storage**: Cloudflare R2

## Prerequisites

- Node.js **20+**
- pnpm **10+** (`npm i -g pnpm`)
- Git

## Setup

```bash
# 1. Clone and install
git clone <repo-url>
cd needhub
pnpm install

# 2. Configure env
cp .env.example apps/api/.env
# Ask the team lead for the shared DATABASE_URL and other secrets
# Paste them into apps/api/.env

# 3. Run the API
pnpm dev:api
```

## Secrets

Nothing sensitive lives in git. Ask a team member (currently: Maitreya) for:

- `DATABASE_URL` — shared Neon Postgres URL
- `CLERK_SECRET_KEY` — Clerk auth
- `LLM_API_KEY` — Grok API key
- `STORAGE_*` — Cloudflare R2 keys

## Database

- Shared Neon project. All contributors use the same DB, so **don't run destructive queries** without asking.
- Schema lives in [apps/api/prisma/schema.prisma](apps/api/prisma/schema.prisma).
- Bootstrap SQL (if setting up a fresh DB) is at [apps/api/prisma/init.sql](apps/api/prisma/init.sql).
- Prisma connects via Neon's HTTPS driver, so no ISP-level Postgres port blocks apply.

## Repo layout

```
needhub/
├── apps/
│   ├── mobile/   # Flutter app (WIP)
│   └── api/      # Node + Express + Prisma
└── packages/
    └── shared/   # Shared TS types
```

## Build order

See [Needhub.txt §9](Needhub.txt) for the vertical-slice build order. Current phase: DB scaffolding complete, moving to Auth + verification.
