#!/bin/sh
# morphic-railway app entrypoint.
#
#   1. validate variables (names only; values are never printed)
#   2. mint the Supabase API keys from JWT_SECRET
#   3. wait for the database and Supabase Auth, create Morphic's database, apply Morphic's migrations
#      (upstream's own script) and the signup gate
#   4. create the owner account
#   5. write the public values into the built app, and only then start the web server
set -u
log()  { printf '[morphic-app] %s\n' "$*"; }
fail() { printf '[morphic-app] FATAL: %s\n' "$*" >&2; exit 1; }

require() {
  for name in "$@"; do
    eval "v=\${$name:-}"
    # shellcheck disable=SC2154  # v is assigned by the eval above
    [ -n "$v" ] || fail "missing required variable: $name"
  done
}
require JWT_SECRET DATABASE_URL SUPABASE_DB_URL SUPABASE_INTERNAL_URL NEXT_PUBLIC_SUPABASE_URL OWNER_EMAIL OWNER_PASSWORD
[ "${#JWT_SECRET}" -ge 32 ] || fail "JWT_SECRET must be at least 32 characters"
case "$JWT_SECRET" in
  your-super-secret-jwt-token-with-at-least-32-characters-long)
    fail "JWT_SECRET is the value from Supabase's public .env.example. Anyone can sign a service_role token with it." ;;
esac
[ "${#OWNER_PASSWORD}" -ge 12 ] || fail "OWNER_PASSWORD must be at least 12 characters"
case "$OWNER_EMAIL" in *@*.*) ;; *) fail "OWNER_EMAIL must be an e-mail address; it is what the owner signs in with" ;; esac

# A Railway reference such as ${{kong.RAILWAY_PRIVATE_DOMAIN}} is empty until that service has a
# deployment, which leaves `http://:8000`. Say so, rather than retry an address that cannot exist.
for name in DATABASE_URL SUPABASE_DB_URL SUPABASE_INTERNAL_URL NEXT_PUBLIC_SUPABASE_URL SEARXNG_API_URL LOCAL_REDIS_URL; do
  eval "v=\${$name:-}"
  case "$v" in
    *://|*://:*|*:///*|*@:*|*@/*)
      fail "$name has no host name. On Railway this is a reference to another service's domain that had not resolved when this deployment started; redeploy once that service has deployed." ;;
  esac
done

# Anonymous mode gives everyone who reaches the domain one shared account on your model keys.
# Upstream intends it for a single person on their own machine; this template does not offer it.
case "${ENABLE_AUTH:-true}" in
  true) ENABLE_AUTH=true ;;
  *) fail "ENABLE_AUTH must stay true on a public deployment. To let more people in, use MORPHIC_ALLOWED_SIGNUPS or MORPHIC_SIGNUP_MODE=open." ;;
esac
: "${ENABLE_GUEST_CHAT:=false}"
: "${SEARCH_API:=searxng}"
: "${MORPHIC_SIGNUP_MODE:=closed}"
case "$MORPHIC_SIGNUP_MODE" in closed|open) ;; *) fail "MORPHIC_SIGNUP_MODE must be closed or open" ;; esac
# Morphic Cloud mode (PostHog analytics, Upstash rate limits) is for the hosted service the Morphic team
# runs; a self-hosted instance runs without it.
MORPHIC_CLOUD_DEPLOYMENT=false
DATABASE_SSL_DISABLED=true
: "${PORT:=3000}"
case "$PORT" in ''|*[!0-9]*) fail "PORT must be a number, got \"$PORT\"" ;; esac
# The search tool calls the app's own advanced-search route through this URL. Pinning it to the local
# listener keeps that call off the public internet and out of reach of a forged Host header.
BASE_URL="http://127.0.0.1:${PORT}"
MORPHIC_RAILWAY_INTERNAL_TOKEN=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
printf '%s' "$MORPHIC_RAILWAY_INTERNAL_TOKEN" | grep -Eqx '[0-9a-f]{64}' || fail "could not generate the internal token"
export ENABLE_AUTH ENABLE_GUEST_CHAT SEARCH_API MORPHIC_SIGNUP_MODE MORPHIC_CLOUD_DEPLOYMENT DATABASE_SSL_DISABLED \
       PORT BASE_URL MORPHIC_RAILWAY_INTERNAL_TOKEN

if [ -z "${OPENAI_API_KEY:-}${ANTHROPIC_API_KEY:-}${GOOGLE_GENERATIVE_AI_API_KEY:-}${AI_GATEWAY_API_KEY:-}${OLLAMA_BASE_URL:-}${OPENAI_COMPATIBLE_API_KEY:-}" ]; then
  log "no AI provider is configured yet: set OPENAI_API_KEY, ANTHROPIC_API_KEY or another provider variable on this service, then redeploy"
fi

keys=$(node /opt/morphic-railway/mint-supabase-keys.mjs) || fail "could not mint the Supabase API keys"
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=$(printf '%s\n' "$keys" | sed -n 's/^ANON_KEY=//p')
SUPABASE_SERVICE_ROLE_KEY=$(printf '%s\n' "$keys" | sed -n 's/^SERVICE_ROLE_KEY=//p')
unset keys
# Morphic's name for the service-role key; it deletes accounts with it.
SUPABASE_SECRET_KEY=$SUPABASE_SERVICE_ROLE_KEY
export NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY SUPABASE_SERVICE_ROLE_KEY SUPABASE_SECRET_KEY

: "${MORPHIC_READY_TIMEOUT:=600}"
deadline=$(( $(date +%s) + MORPHIC_READY_TIMEOUT ))
wait_for() {
  what=$1; shift
  until "$@" >/dev/null 2>&1; do
    [ "$(date +%s)" -lt "$deadline" ] || fail "$what did not become ready within ${MORPHIC_READY_TIMEOUT}s"
    sleep 3
  done
  log "$what is ready"
}
auth_ok() {
  node -e '
    const k = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
    fetch(process.env.SUPABASE_INTERNAL_URL.replace(/\/+$/,"") + "/auth/v1/health", { headers: { apikey: k } })
      .then(r => process.exit(r.status === 200 ? 0 : 1)).catch(() => process.exit(1))'
}
db() { node /opt/morphic-railway/railway-db.mjs "$@"; }

# Supabase Auth creates the auth schema on its first start, and the gate adds a trigger to auth.users.
wait_for "the database" db wait SUPABASE_DB_URL
wait_for "the gateway and Supabase Auth" auth_ok

db ensure-database || fail "could not create Morphic's database"
log "applying Morphic migrations"
if ! (cd /app && bun run lib/db/migrate.ts > /tmp/morphic-migrate.log 2>&1); then
  grep -iE 'error|failed' /tmp/morphic-migrate.log | tail -5 >&2
  fail "Morphic migrations failed; refusing to start on a partial schema"
fi
rm -f /tmp/morphic-migrate.log
log "migrations applied"

db apply /opt/morphic-railway/gate.sql || fail "could not install the signup gate"
db signup-policy || fail "could not record the signup policy"

# The gate admits the owner by a one-time nonce: 32 random bytes, only their hash stored, consumed by
# the insert and removed again whatever happens.
MORPHIC_BOOTSTRAP_NONCE=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
printf '%s' "$MORPHIC_BOOTSTRAP_NONCE" | grep -Eqx '[0-9a-f]{64}' || fail "could not generate the bootstrap nonce"
db nonce-set "$(printf '%s' "$MORPHIC_BOOTSTRAP_NONCE" | sha256sum | cut -d' ' -f1)" || fail "could not register the bootstrap nonce"
export MORPHIC_BOOTSTRAP_NONCE
node /opt/morphic-railway/bootstrap-owner.mjs; status=$?
unset MORPHIC_BOOTSTRAP_NONCE
db nonce-clear || true
[ "$status" -eq 0 ] || fail "could not create the owner account"

node /opt/morphic-railway/fill-public-env.mjs || exit 1
unset SUPABASE_SERVICE_ROLE_KEY JWT_SECRET SUPABASE_DB_URL

log "search: ${SEARCH_API}"
log "starting Morphic on [::]:${PORT}"
cd /app && exec node node_modules/next/dist/bin/next start -H :: -p "$PORT"
