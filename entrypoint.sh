#!/bin/sh
set -e
cd /app
exec node apps/api/dist/index.js
