#!/usr/bin/env bash
# shellcheck disable=SC2013,SC2015,SC2016  # single-quoted literals are matched, not expanded
# Public smoke test against a deployed bundle.
#   tests/railway-smoke.sh https://app-domain https://supabase-gateway-domain
# Optional:
#   OWNER_EMAIL=... OWNER_PASSWORD_FILE=/path   sign in as the owner (the file holds the password)
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
usage="usage: railway-smoke.sh https://app https://supabase-gateway"
APP_URL=${1:?$usage}; APP_URL=${APP_URL%/}
GATEWAY_URL=${2:?$usage}; GATEWAY_URL=${GATEWAY_URL%/}
export APP_URL GATEWAY_URL
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
umask 077

section "TLS and routing"
# Railway's edge serves 404 for a few seconds while a deployment takes over.
wait_for_code "$APP_URL/auth/login" 200 600 || true
assert_eq "the app serves its sign-in page over https" "200" "$(http_code "$APP_URL/auth/login")"
assert_contains "valid certificate on the app" "SSL certificate verify ok" "$(curl -sv -o /dev/null "$APP_URL/auth/login" 2>&1 || true)"
assert_contains "valid certificate on the gateway" "SSL certificate verify ok" "$(curl -sv -o /dev/null "$GATEWAY_URL/auth/v1/health" 2>&1 || true)"
host=${APP_URL#https://}
assert_contains "http -> https" "https://$host" "$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 20 "http://$host/auth/login")"

section "the browser bundle carries this deployment's values"
login=$(curl -s --max-time 30 "$APP_URL/auth/login" || true)
anon=""; found_gateway=0; placeholder=0
for js in $(grep -oE '/_next/static/[^"]+\.js' <<<"$login" | sort -u | head -80); do
  chunk=$(curl -s --max-time 20 "$APP_URL$js" || true)
  grep -q 'morphic-railway-placeholder-' <<<"$chunk" && placeholder=1
  grep -q "$GATEWAY_URL" <<<"$chunk" && found_gateway=1
  [ -n "$anon" ] || anon=$(grep -oE 'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' <<<"$chunk" | head -1 || true)
done
[ "$placeholder" = 0 ] && pass "no build placeholder left" || fail "a build placeholder survived in the app"
[ "$found_gateway" = 1 ] && pass "the app points at this Supabase gateway" || fail "no chunk carries the gateway URL"
[ -n "$anon" ] && pass "found the public anon key the browser uses" || fail "could not find the anon key in the app"
printf 'ANON_KEY=%s\n' "$anon" > "$TEST_TMP/keys"

section "the Supabase gateway"
assert_eq "no API key, no entry" "401" "$(http_code "$GATEWAY_URL/auth/v1/settings")"
assert_eq "Supabase Auth answers with the anon key" "200" "$(http_code "$GATEWAY_URL/auth/v1/settings" -H "apikey: $anon")"
assert_eq "REST is not routed" "404" "$(http_code "$GATEWAY_URL/rest/v1/" -H "apikey: $anon")"
head -c 18 /dev/urandom | base64 | tr -d '/+=\n' > "$TEST_TMP/probe-pw"
assert_eq "a stranger's signup is refused" "500" "$(sign_up "probe-$(date +%s)@example.com" "$TEST_TMP/probe-pw")"

section "the app"
chat='{"trigger":"submit-message","chatId":"probe-chat","isNewChat":true,"message":{"id":"m1","role":"user","parts":[{"type":"text","text":"hi"}]}}'
assert_eq "anonymous chat is refused" "401" "$(http_code -X POST "$APP_URL/api/chat" -H 'Content-Type: application/json' --data "$chat")"
assert_eq "advanced search is closed to the outside" "404" "$(http_code -X POST "$APP_URL/api/advanced-search" -H 'Content-Type: application/json' --data '{"query":"probe","maxResults":1}')"

if [ -n "${OWNER_EMAIL:-}" ] && [ -n "${OWNER_PASSWORD_FILE:-}" ]; then
  section "signed in as the owner"
  sign_in "$OWNER_EMAIL" "$OWNER_PASSWORD_FILE" "$TEST_TMP/owner-token" && pass "owner signs in" || fail "owner sign-in failed"
  if [ -s "$TEST_TMP/owner-token" ]; then
    assert_eq "the app accepts the owner's session" "200" "$(app_code_as "$TEST_TMP/owner-token" GET '/api/chats?offset=0&limit=1')"
    if [ "${CHAT:-0}" = 1 ]; then
      reply=$(chat_as "$TEST_TMP/owner-token" "railway-smoke-$(date +%s)" "Reply with one short sentence." | stream_text)
      [ -n "$reply" ] && pass "the configured model answers a chat" || fail "no answer from the configured model"
    fi
  fi
fi
summary
