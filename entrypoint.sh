#!/bin/sh
# Ignore all arguments passed by Railway (including "cd ../..").
# Always run our compiled server from the guaranteed /app directory.
set -e
cd /app

echo "[entrypoint] Applying pending Prisma migrations..."
# Deploy migrations before starting. Never fail startup on migrate errors —
# some DBs (e.g. hackathon-seeded ones) may already be at head, in which
# case migrate deploy is a no-op. Fresh DBs get schema applied here.
node_modules/.bin/prisma migrate deploy --schema apps/api/prisma/schema.prisma \
  || echo "[entrypoint] prisma migrate deploy reported an issue — continuing"

echo "[entrypoint] NeedHub API starting on port ${PORT:-3000}..."
exec node apps/api/dist/index.js
