#!/bin/sh
# Ignore all arguments passed by Railway (including "cd ../..").
# Always run our compiled server from the guaranteed /app directory.
set -e
cd /app

echo "[entrypoint] Applying pending Prisma migrations..."
# Deploy migrations before starting. Never fail startup on migrate errors —
# fresh DBs get schema applied here; already-migrated DBs are a no-op.
# We try multiple locations for the prisma binary because pnpm's layout
# depends on hoisting settings.
set +e
if command -v pnpm >/dev/null 2>&1; then
  echo "[entrypoint] using pnpm exec"
  pnpm --filter @needhub/api exec prisma migrate deploy
elif [ -x apps/api/node_modules/.bin/prisma ]; then
  echo "[entrypoint] using apps/api/node_modules/.bin/prisma"
  (cd apps/api && node_modules/.bin/prisma migrate deploy)
elif [ -x node_modules/.bin/prisma ]; then
  echo "[entrypoint] using root node_modules/.bin/prisma"
  node_modules/.bin/prisma migrate deploy --schema apps/api/prisma/schema.prisma
else
  echo "[entrypoint] ERROR: no prisma binary found — schema will be out of sync"
  ls -la apps/api/node_modules/.bin/ 2>&1 | head -20
  ls -la node_modules/.bin/ 2>&1 | head -20
fi
MIGRATE_EXIT=$?
echo "[entrypoint] prisma migrate deploy exit=$MIGRATE_EXIT"
set -e

echo "[entrypoint] NeedHub API starting on port ${PORT:-3000}..."
exec node apps/api/dist/index.js
