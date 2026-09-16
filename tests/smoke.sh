#!/usr/bin/env bash
# shellcheck disable=SC2013,SC2015,SC2016  # single-quoted literals are matched, not expanded
# Local smoke test of the whole bundle on fresh volumes.
# Run `docker compose build` first (CI does), or set the MORPHIC_RAILWAY_*_IMAGE overrides.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
mkdir -p "$REPO_ROOT/test-output"; METRICS="$REPO_ROOT/test-output/metrics.txt"
umask 077

JWT='local-test-only-jwt-secret-000000000000000000000000000000'
OWNER_EMAIL='owner@example.com'
printf '%s' 'local-test-only-owner-password' > "$TEST_TMP/owner-pw"
printf '%s' 'someone-else-password-1' > "$TEST_TMP/other-pw"
mint_keys "$JWT"
SECRETS=(
  "$JWT" 'localtestonlypostgrespassword' 'local-test-only-owner-password' 'local-test-only-searxng-secret'
  'localtestonlyredispassword' "$(service_key | tail -c 40)"
)

section "fresh stack (empty volumes)"
compose down -v --remove-orphans >/dev/null 2>&1 || true
t0=$(date +%s); compose up -d --no-build
wait_for_code "$APP_URL/auth/login" 200 "$TEST_TIMEOUT" && pass "the app serves its sign-in page" \
  || { compose logs --no-color --tail 60 app db auth kong; die "the app never became ready"; }
cold=$(( $(date +%s) - t0 )); echo "cold_start_seconds=$cold" | tee "$METRICS"

section "first boot"
logs=$(compose logs --no-color --no-log-prefix app)
assert_contains "waited for Supabase Auth" "the gateway and Supabase Auth is ready" "$logs"
assert_contains "created Morphic's own database" "created the morphic database" "$logs"
assert_contains "applied Morphic's migrations" "migrations applied" "$logs"
assert_contains "signup is closed, with the allowlist" "signup: closed, 2 allowlist entries" "$logs"
assert_contains "created the owner, e-mail masked" "owner account created for o\*\*\*@example.com" "$logs"
assert_contains "wrote the public values" "public values written into" "$logs"
assert_contains "and only then started the server" "starting Morphic" "$logs"
assert_contains "search goes to SearXNG" "search: searxng" "$logs"
assert_not_contains "no provider warning (the stand-in provider is set)" "no AI provider is configured" "$logs"
all=$(compose logs --no-color 2>&1)
for s in "${SECRETS[@]}"; do assert_not_contains "no secret in any service log (probe len ${#s})" "$s" "$all"; done
assert_not_contains "Kong does not print its request-debug token" "token for request debugging" "$all"
assert_eq "Morphic's tables are in their own database" "1" "$(psql_morphic "select count(*) from pg_tables where schemaname = 'public' and tablename = 'chats'")"
assert_eq "and not in Supabase's" "0" "$(psql_admin "select count(*) from pg_tables where schemaname = 'public' and tablename = 'chats'")"

section "the owner"
sign_in "$OWNER_EMAIL" "$TEST_TMP/owner-pw" "$TEST_TMP/owner-token" && pass "owner signs in through the gateway" || die "owner sign-in failed"
printf '%s' 'wrong-password-entirely' > "$TEST_TMP/wrong-pw"
sign_in "$OWNER_EMAIL" "$TEST_TMP/wrong-pw" "$TEST_TMP/nothing" && fail "wrong password accepted" || pass "wrong password refused"
assert_eq "no bootstrap nonce is stored" "0" "$(psql_admin "select count(*) from auth.users where raw_user_meta_data ? 'morphic_railway_bootstrap_nonce'")"
assert_eq "and none is left in the gate" "0" "$(psql_admin "select count(*) from morphic_railway.settings where key = 'bootstrap_nonce_sha256'")"
assert_eq "the owner's session cookie is accepted by the app" "200" "$(app_code_as "$TEST_TMP/owner-token" GET '/api/chats?offset=0&limit=1')"

section "nobody else signs up"
assert_eq "a stranger's signup is refused" "500" "$(sign_up stranger@example.com "$TEST_TMP/other-pw")"
assert_eq "so is one that forges a bootstrap nonce" "500" \
  "$(sign_up forger@example.com "$TEST_TMP/other-pw" '{"morphic_railway_bootstrap_nonce":"0000000000000000000000000000000000000000000000000000000000000000"}')"
assert_eq "so is a look-alike of an allowlisted domain" "500" "$(sign_up someone@evilteam.example.com "$TEST_TMP/other-pw")"
assert_eq "no user was created" "1" "$(psql_admin 'select count(*) from auth.users')"
assert_eq "an allowlisted address is admitted" "200" "$(sign_up friend@example.com "$TEST_TMP/other-pw")"
assert_eq "so is an address at an allowlisted domain" "200" "$(sign_up colleague@team.example.com "$TEST_TMP/other-pw")"
assert_eq "anonymous chat is refused" "401" "$(http_code -X POST "$APP_URL/api/chat" -H 'Content-Type: application/json' \
  --data '{"trigger":"submit-message","chatId":"anon-chat","isNewChat":true,"message":{"id":"m1","role":"user","parts":[{"type":"text","text":"hi"}]}}')"

section "a chat, end to end"
reply=$(chat_as "$TEST_TMP/owner-token" smoke-chat-1 "What is the capital of France?" | stream_text)
assert_contains "the model's answer streams back" "Mock model answer: the bundle works." "$reply"
saved=""
for _ in $(seq 1 20); do
  saved=$(psql_morphic "select p.text_text from parts p join messages m on m.id = p.message_id
    where m.chat_id = 'smoke-chat-1' and m.role = 'assistant' and p.type = 'text'" | tr -d '\n')
  [ -n "$saved" ] && break; sleep 1
done
assert_contains "the answer is saved with the chat" "Mock model answer: the bundle works." "$saved"
owner_id=$(psql_admin "select id from auth.users where email = 'owner@example.com'")
assert_eq "under the owner's id" "$owner_id" "$(psql_morphic "select user_id from chats where id = 'smoke-chat-1'")"
sign_in friend@example.com "$TEST_TMP/other-pw" "$TEST_TMP/friend-token" && pass "the allowlisted user signs in" || fail "allowlisted sign-in failed"
assert_not_contains "another user's chat list does not show it" "smoke-chat-1" "$(app_as "$TEST_TMP/friend-token" GET '/api/chats?offset=0&limit=20')"
assert_contains "the owner's does" "smoke-chat-1" "$(app_as "$TEST_TMP/owner-token" GET '/api/chats?offset=0&limit=20')"
assert_not_contains "a visitor cannot open the conversation" "capital of France" "$(curl -s --max-time 30 "$APP_URL/search/smoke-chat-1" || true)"
assert_not_contains "nor can another user" "capital of France" "$(app_as "$TEST_TMP/friend-token" GET /search/smoke-chat-1)"
assert_contains "its owner can" "capital of France" "$(app_as "$TEST_TMP/owner-token" GET /search/smoke-chat-1)"

section "search"
body='{"query":"railway app hosting","maxResults":3,"searchDepth":"basic"}'
assert_eq "advanced search is closed to the outside" "404" "$(http_code -X POST "$APP_URL/api/advanced-search" -H 'Content-Type: application/json' --data "$body")"
assert_eq "even to a signed-in user" "404" "$(app_code_as "$TEST_TMP/owner-token" POST /api/advanced-search -H 'Content-Type: application/json' --data "$body")"
assert_eq "and to a made-up token" "404" "$(http_code -X POST "$APP_URL/api/advanced-search" -H 'Content-Type: application/json' \
  -H "x-morphic-railway-internal: $(printf '0%.0s' $(seq 1 64))" --data "$body")"
internal_token > "$TEST_TMP/internal-token"
assert_eq "the app holds a 64-character internal token" "64" "$(tr -d '\n' < "$TEST_TMP/internal-token" | wc -c | tr -d ' ')"
res=$(compose exec -T app node -e '
  const t = require("fs").readFileSync(0, "utf8").trim();
  fetch("http://127.0.0.1:3000/api/advanced-search", { method: "POST",
    headers: { "Content-Type": "application/json", "x-morphic-railway-internal": t },
    body: process.argv[1] })
    .then(async r => { const j = await r.json().catch(() => null); console.log(r.status, Array.isArray(j?.results)); })
    .catch(e => console.log("error", e.message))' "$body" < "$TEST_TMP/internal-token" || true)
rm -f "$TEST_TMP/internal-token"
assert_eq "the app's own search tool reaches SearXNG through it" "200 true" "$res"
assert_eq "SearXNG answers JSON on the private network" "200" "$(compose exec -T app node -e '
  fetch("http://searxng:8080/search?q=test&format=json").then(r => console.log(r.status)).catch(() => console.log("error"))' || true)"
assert_eq "and serves no HTML interface" "403" "$(compose exec -T app node -e '
  fetch("http://searxng:8080/search?q=test&format=html").then(r => console.log(r.status)).catch(() => console.log("error"))' || true)"
assert_contains "Valkey refuses a client without the password" "NOAUTH" "$(compose exec -T redis valkey-cli ping 2>&1 || true)"

section "the Supabase gateway"
assert_eq "no API key, no entry" "401" "$(http_code "$GATEWAY_URL/auth/v1/settings")"
assert_eq "Auth answers with the anon key" "200" "$(http_code "$GATEWAY_URL/auth/v1/settings" -H "apikey: $(anon_key)")"
assert_eq "REST is not routed" "404" "$(http_code "$GATEWAY_URL/rest/v1/" -H "apikey: $(anon_key)")"
assert_eq "nor is Storage" "404" "$(http_code "$GATEWAY_URL/storage/v1/bucket" -H "apikey: $(anon_key)")"

section "the browser bundle"
login=$(curl -s --max-time 30 "$APP_URL/auth/login")
found_url=0; found_key=0; placeholder=0; service=0
for js in $(grep -oE '/_next/static/[^"]+\.js' <<<"$login" | sort -u); do
  chunk=$(curl -s --max-time 20 "$APP_URL$js" || true)
  grep -q 'morphic-railway-placeholder-' <<<"$chunk" && placeholder=1
  grep -q "$GATEWAY_URL" <<<"$chunk" && found_url=1
  grep -q "$(anon_key)" <<<"$chunk" && found_key=1
  grep -q "$(service_key)" <<<"$chunk" && service=1
done
[ "$placeholder" = 0 ] && pass "no build placeholder left" || fail "a build placeholder survived"
[ "$found_url" = 1 ] && pass "the browser talks to this gateway" || fail "no chunk carries the gateway URL"
[ "$found_key" = 1 ] && pass "with the anon key" || fail "no chunk carries the anon key"
[ "$service" = 0 ] && pass "the service-role key is not in the browser" || fail "the service-role key is in a browser chunk"

section "restart is idempotent"
compose restart app >/dev/null
sleep 5
wait_for_code "$APP_URL/auth/login" 200 300 && pass "the app comes back" || fail "the app did not come back"
logs=$(compose logs --no-color --no-log-prefix app)
assert_contains "the owner is left alone" "owner account exists from an earlier start; leaving it alone" "$logs"
assert_eq "still exactly one owner" "1" "$(psql_admin "select count(*) from auth.users where email = 'owner@example.com'")"
sign_in "$OWNER_EMAIL" "$TEST_TMP/owner-pw" "$TEST_TMP/owner-token" && pass "and can still sign in" || fail "owner sign-in failed after restart"

section "fail fast"
APP_ENV=(-e JWT_SECRET="$JWT" -e DATABASE_URL=postgresql://postgres:x@db:5432/morphic -e SUPABASE_DB_URL=postgresql://postgres:x@db:5432/postgres
         -e SUPABASE_INTERNAL_URL=http://kong:8000 -e OWNER_EMAIL=o@example.com -e OWNER_PASSWORD=long-enough-password)
out=$(docker run --rm -e JWT_SECRET=short "$(service_image app)" 2>&1 || true)
assert_contains "the app refuses a missing variable" "missing required variable" "$out"
out=$(docker run --rm "${APP_ENV[@]}" -e NEXT_PUBLIC_SUPABASE_URL=https://kong.example.com -e ENABLE_AUTH=false "$(service_image app)" 2>&1 || true)
assert_contains "and anonymous mode" "ENABLE_AUTH must stay true" "$out"
out=$(docker run --rm "${APP_ENV[@]}" -e NEXT_PUBLIC_SUPABASE_URL=https://:8000 "$(service_image app)" 2>&1 || true)
assert_contains "and an unresolved Railway reference" "NEXT_PUBLIC_SUPABASE_URL has no host name" "$out"
out=$(docker run --rm "$(service_image searxng)" 2>&1 || true)
assert_contains "SearXNG refuses to start without a secret" "missing required variable: SEARXNG_SECRET" "$out"
out=$(docker run --rm -e SEARXNG_SECRET=ultrasecretkey "$(service_image searxng)" 2>&1 || true)
assert_contains "or with a short one" "SEARXNG_SECRET must be at least 32 characters" "$out"

section "shutdown"
compose stop >/dev/null && pass "stack stops cleanly"
summary
