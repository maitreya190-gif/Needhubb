# BUILD_MARKER_ZEBRA_2026
FROM node:22-alpine
WORKDIR /app
RUN apk add --no-cache openssl
RUN corepack enable && corepack prepare pnpm@9.15.9 --activate

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/api/package.json ./apps/api/
COPY packages/shared/package.json ./packages/shared/

RUN pnpm install --frozen-lockfile

COPY . .

RUN pnpm --filter @needhub/api exec prisma generate
RUN pnpm --filter @needhub/api build

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
    && ln -sf /entrypoint.sh /usr/local/bin/cd \
    && ln -sf /entrypoint.sh /usr/local/bin/start \
    && ln -sf /entrypoint.sh /usr/local/bin/pnpm-start

ENV NODE_ENV=production
EXPOSE 3000
CMD ["/entrypoint.sh"]
ENTRYPOINT ["/entrypoint.sh"]
