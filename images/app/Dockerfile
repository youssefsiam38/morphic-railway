# syntax=docker/dockerfile:1
#
# Morphic for Railway.
#
# Upstream's published image is built without Supabase, which leaves Morphic in anonymous mode: one
# shared account for everyone who reaches the domain. Sign-in needs the Supabase URL and key, and
# Next.js inlines NEXT_PUBLIC_* values into the bundle at build time. A one-click template cannot
# rebuild per deploy with values that do not exist yet (the gateway's domain, a key signed with a
# generated secret), so this image is built once, from a pinned upstream release, with unmistakable
# placeholder values, and the entrypoint writes the real values into the built files at start-up.
#
# One upstream behaviour is patched, and the build fails if the patch stops applying: the
# advanced-search route only answers the app's own search tool (patch-advanced-search.mjs).
ARG NODE_IMAGE=docker.io/library/node:22-slim@sha256:83f487e0a63425e5b4d146fb5e5be574bcbe1b7b843d3ebafdd95eaf7767a7e5
ARG MORPHIC_COMMIT=514c8cc562ada40f5f0cafddfd9cb9874cd6c01c
ARG BUN_VERSION=1.4.2

# ---------------------------------------------------------------------------------------------
# Upstream source at an exact commit (release v1.7.0). Fetching by commit id makes git verify it.
# ---------------------------------------------------------------------------------------------
FROM ${NODE_IMAGE} AS source
ARG MORPHIC_COMMIT
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends git ca-certificates >/dev/null \
    && git init -q /src \
    && git -C /src fetch -q --depth 1 https://github.com/miurla/morphic.git "${MORPHIC_COMMIT}" \
    && git -C /src checkout -q FETCH_HEAD \
    && test "$(git -C /src rev-parse HEAD)" = "${MORPHIC_COMMIT}" \
    && rm -rf /src/.git
COPY images/app/patch-advanced-search.mjs /tmp/patch-advanced-search.mjs
RUN node /tmp/patch-advanced-search.mjs /src

# ---------------------------------------------------------------------------------------------
# Dependencies and build, as upstream's own Dockerfile does them.
# ---------------------------------------------------------------------------------------------
FROM ${NODE_IMAGE} AS builder
ARG BUN_VERSION
WORKDIR /app
RUN npm install -g "bun@${BUN_VERSION}" >/dev/null && bun --version
COPY --from=source /src/package.json /src/bun.lock ./
RUN bun install --frozen-lockfile
COPY --from=source /src/ ./
# Placeholders, replaced at start-up by images/app/fill-public-env.mjs. URL-shaped where the build may
# parse them; `.invalid` is reserved and can never resolve. DATABASE_URL is upstream's build-time dummy.
ENV NEXT_PUBLIC_SUPABASE_URL=https://morphic-railway-placeholder-supabase-url.invalid \
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=morphic-railway-placeholder-supabase-publishable-key \
    DATABASE_URL=postgresql://user:pass@localhost:5432/db \
    NEXT_TELEMETRY_DISABLED=1
RUN npm run build
# Record every built file that carries a placeholder, and keep a pristine copy of each, so that the
# values can be written again on every start rather than only on the first.
COPY images/app/fill-public-env.mjs /tmp/fill-public-env.mjs
RUN node /tmp/fill-public-env.mjs --index /app/.next /opt/morphic-railway/pristine \
    && rm -rf /app/.next/cache

# ---------------------------------------------------------------------------------------------
# Runtime: the same files upstream's image ships
# ---------------------------------------------------------------------------------------------
FROM ${NODE_IMAGE} AS runner
ARG BUN_VERSION
ARG MORPHIC_COMMIT
ARG MORPHIC_VERSION=1.7.0
ARG WRAPPER_VERSION=0.0.0-dev
ARG VCS_REF=unknown
ARG BUILD_DATE=1970-01-01T00:00:00Z

WORKDIR /app
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    MORPHIC_COMMIT=${MORPHIC_COMMIT}

# bun runs upstream's migration script, as in upstream's image.
RUN npm install -g "bun@${BUN_VERSION}" >/dev/null && bun --version && npm cache clean --force >/dev/null 2>&1

COPY --from=builder --chown=node:node /app/.next ./.next
COPY --from=builder --chown=node:node /app/public ./public
COPY --from=builder /app/package.json /app/bun.lock ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/drizzle ./drizzle
COPY --from=builder /app/lib/db ./lib/db
COPY --from=builder /app/drizzle.config.ts /app/tsconfig.json ./
COPY --from=builder --chown=node:node /opt/morphic-railway/pristine /opt/morphic-railway/pristine
COPY lib/mint-supabase-keys.mjs /opt/morphic-railway/mint-supabase-keys.mjs
COPY images/app/fill-public-env.mjs /opt/morphic-railway/fill-public-env.mjs
COPY images/app/railway-db.mjs /opt/morphic-railway/railway-db.mjs
COPY images/app/bootstrap-owner.mjs /opt/morphic-railway/bootstrap-owner.mjs
COPY images/app/gate.sql /opt/morphic-railway/gate.sql
COPY --chmod=0755 images/app/entrypoint.sh /usr/local/bin/morphic-railway-entrypoint
COPY licenses/ /usr/share/licenses/morphic-railway/

# The server and the browser chunks must both carry the placeholders, the patch must be in the build,
# and the migration script must be where the entrypoint runs it.
RUN test -s /opt/morphic-railway/pristine/.index \
    && grep -q '^.next/static/' /opt/morphic-railway/pristine/.index \
    && grep -q '^.next/server/' /opt/morphic-railway/pristine/.index \
    && grep -rqs 'x-morphic-railway-internal' /app/.next/server \
    && test -f /app/lib/db/migrate.ts && ls /app/drizzle/0000_*.sql >/dev/null

USER node

LABEL org.opencontainers.image.title="morphic-railway-app" \
      org.opencontainers.image.description="Morphic, the AI answer engine, built for the Railway template: sign-in through a bundled Supabase Auth, migrations, closed signup and the owner account handled at start-up. Not affiliated with the Morphic project." \
      org.opencontainers.image.source="https://github.com/youssefsiam38/morphic-railway" \
      org.opencontainers.image.url="https://github.com/youssefsiam38/morphic-railway" \
      org.opencontainers.image.documentation="https://github.com/youssefsiam38/morphic-railway#readme" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${WRAPPER_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      io.morphic-railway.upstream.commit="${MORPHIC_COMMIT}" \
      io.morphic-railway.upstream.version="${MORPHIC_VERSION}"

EXPOSE 3000

ENTRYPOINT ["/usr/local/bin/morphic-railway-entrypoint"]
