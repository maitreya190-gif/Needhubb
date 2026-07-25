#!/bin/sh
# Ignore all arguments passed by Railway (including "cd ../..").
# Always run our compiled server from the guaranteed /app directory.
set -e
cd /app
echo "[entrypoint] NeedHub API starting on port ${PORT:-3000}..."
exec node apps/api/dist/index.js
