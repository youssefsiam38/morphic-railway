#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016  # single-quoted literals are matched, not expanded
# Static validation: syntax, shellcheck, compose, image pins, key minting, security defaults.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
cd "$REPO_ROOT"
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"

section "syntax"
for f in images/*/*.sh tests/*.sh; do
  if bash -n "$f" 2>/dev/null; then pass "parses: $f"; else fail "syntax error: $f"; fi
done
for f in lib/*.mjs images/*/*.mjs; do
  if node --check "$f" 2>/dev/null; then pass "parses: $f"; else fail "syntax error: $f"; fi
done
if perl -c images/kong/mint-keys.pl >/dev/null 2>&1; then pass "parses: images/kong/mint-keys.pl"; else fail "syntax error: images/kong/mint-keys.pl"; fi
if python3 -m py_compile tests/mock-llm.py 2>/dev/null; then pass "parses: tests/mock-llm.py"; else fail "syntax error: tests/mock-llm.py"; fi

section "shellcheck"
if command -v shellcheck >/dev/null; then
  if shellcheck images/*/*.sh; then pass "shellcheck images"; else fail "shellcheck images"; fi
  if shellcheck -x -s bash tests/*.sh; then pass "shellcheck tests"; else fail "shellcheck tests"; fi
else
  echo "  SKIP  shellcheck not installed"
fi

section "compose"
if docker compose -f compose.yaml config -q; then pass "compose config"; else fail "compose config"; fi
cfg=$(COMPOSE_PROFILES='' docker compose -f compose.yaml config --format json)
assert_eq "six services, as on Railway" "6" "$(jq '.services | length' <<<"$cfg")"
assert_eq "the stand-in model provider is a test-only profile" "mock-llm" \
  "$(docker compose -f compose.yaml --profile mock-llm config --format json | jq -r '.services["mock-llm"].profiles | join(",")')"
assert_eq "only the app and the Supabase gateway publish ports" "app kong" \
  "$(jq -r '[.services | to_entries[] | select(.value.ports) | .key] | sort | join(" ")' <<<"$cfg")"
assert_eq "published ports bind to loopback" "127.0.0.1 127.0.0.1" \
  "$(jq -r '[.services[] | .ports[]? | .host_ip] | join(" ")' <<<"$cfg")"
for svc in auth redis; do
  img=$(jq -r --arg s "$svc" '.services[$s].image' <<<"$cfg")
  [[ "$img" == *:*@sha256:* ]] && pass "$svc pinned by tag and digest" || fail "$svc image not pinned: $img"
done
assert_contains "the mock provider image is pinned too" "python:3.13-alpine@sha256:" "$(cat compose.yaml)"
assert_eq "the test network has IPv6, like Railway's" "true" "$(jq -r '.networks.default.enable_ipv6' <<<"$cfg")"
assert_eq "Valkey requires its password, expanded by a shell" 'exec valkey-server --requirepass "$$REDIS_PASSWORD" --bind :: 0.0.0.0' \
  "$(jq -r '.services.redis.command[2]' <<<"$cfg")"
assert_eq "Morphic's data lives in its own database" "morphic" "$(jq -r '.services.app.environment.DATABASE_URL' <<<"$cfg" | sed -E 's#.*/##')"

section "images are pinned"
for df in images/*/Dockerfile; do
  base=$(grep -E '^ARG [A-Z_]+_IMAGE=' "$df")
  [ -n "$base" ] || { fail "$df has no pinned base image argument"; continue; }
  if grep -vqE '@sha256:[0-9a-f]{64}$' <<<"$base"; then fail "$df base image lacks a digest"; else pass "$df base pinned by digest"; fi
done
assert_contains "Morphic is built from an exact commit" 'ARG MORPHIC_COMMIT=[0-9a-f]\{40\}' "$(cat images/app/Dockerfile)"
assert_contains "the commit is verified after fetching" 'test "$(git -C /src rev-parse HEAD)" = "${MORPHIC_COMMIT}"' "$(cat images/app/Dockerfile)"
assert_contains "bun is pinned" 'ARG BUN_VERSION=[0-9]' "$(cat images/app/Dockerfile)"
assert_contains "dependencies come from upstream's lockfile" 'bun install --frozen-lockfile' "$(cat images/app/Dockerfile)"
for v in JWT_SECRET POSTGRES_PASSWORD OWNER_PASSWORD SEARXNG_SECRET REDIS_PASSWORD SUPABASE_SECRET_KEY SUPABASE_SERVICE_ROLE_KEY; do
  if grep -qE "^\s+$v=|^ENV $v=|ARG $v" images/*/Dockerfile; then fail "$v is baked into an image"; else pass "no $v in any image"; fi
done

section "the key minters agree"
# Kong's key-auth compares API keys as strings, so every minter must produce byte-identical keys.
secret=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
node_out=$(JWT_SECRET="$secret" node lib/mint-supabase-keys.mjs)
perl_out=$(JWT_SECRET="$secret" perl images/kong/mint-keys.pl)
assert_eq "node and perl minters produce identical keys" "$(sha256sum <<<"$node_out" | cut -c1-16)" "$(sha256sum <<<"$perl_out" | cut -c1-16)"
anon=$(sed -n 's/^ANON_KEY=//p' <<<"$node_out")
b64url_decode() { local s=${1//-/+}; s=${s//_//}; while [ $(( ${#s} % 4 )) -ne 0 ]; do s="$s="; done; base64 -d <<<"$s"; }
assert_eq "anon key carries the anon role" "anon" "$(jq -r .role <<<"$(b64url_decode "$(cut -d. -f2 <<<"$anon")")")"
sig_openssl=$(printf '%s' "$(cut -d. -f1-2 <<<"$anon")" | openssl dgst -sha256 -hmac "$secret" -binary | base64 | tr '+/' '-_' | tr -d '=')
assert_eq "signature verifies independently with openssl" "$sig_openssl" "$(cut -d. -f3 <<<"$anon")"
if JWT_SECRET=short node lib/mint-supabase-keys.mjs >/dev/null 2>&1; then fail "node minter accepted a short secret"; else pass "node minter refuses a short secret"; fi

section "who gets in"
gate=$(cat images/app/gate.sql)
assert_contains "the gate is a BEFORE INSERT trigger on auth.users" 'before insert on auth.users' "$gate"
assert_contains "the owner nonce is single-use" "delete from morphic_railway.settings" "$gate"
assert_contains "the allowlist matches whole addresses or whole domains" "entry = v_email or entry = '@' || split_part(v_email, '@', 2)" "$gate"
ep=$(cat images/app/entrypoint.sh)
assert_contains "the app refuses Supabase's example JWT secret" 'your-super-secret-jwt-token-with-at-least-32-characters-long' "$ep"
assert_contains "signup defaults to closed" ': "${MORPHIC_SIGNUP_MODE:=closed}"' "$ep"
assert_contains "anonymous mode is refused" 'ENABLE_AUTH must stay true' "$ep"
assert_contains "guest chat defaults to off" ': "${ENABLE_GUEST_CHAT:=false}"' "$ep"
assert_contains "migrations failing stop the start" 'refusing to start on a partial schema' "$ep"
created=$(grep -n 'bootstrap-owner.mjs; status' images/app/entrypoint.sh | cut -d: -f1)
started=$(grep -n 'exec node node_modules/next/dist/bin/next start' images/app/entrypoint.sh | cut -d: -f1)
[ "$created" -lt "$started" ] && pass "the owner is created before the server starts" || fail "the server starts before the owner exists"
assert_contains "the claim is the owner's own account, not any account" 'findUserByEmail(EMAIL)' "$(cat images/app/bootstrap-owner.mjs)"
assert_contains "the search tool's self-call stays on the local listener" 'BASE_URL="http://127.0.0.1:${PORT}"' "$ep"

section "the advanced-search patch"
patch=$(cat images/app/patch-advanced-search.mjs)
assert_contains "the patch fails the build unless it matches exactly once" 'found.length !== 1' "$patch"
assert_contains "the route compares the token in constant time" 'timingSafeEqual' "$patch"
assert_contains "and refuses short or missing tokens" 'expected.length < 32' "$patch"
assert_contains "the image build checks the patch is in the server bundle" "grep -rqs 'x-morphic-railway-internal' /app/.next/server" "$(cat images/app/Dockerfile)"

section "search backend"
sx=$(cat images/searxng/settings.yml)
assert_contains "SearXNG serves JSON only" 'formats:' "$sx"
assert_not_contains "and no HTML format" '- html' "$sx"
assert_contains "it refuses to start without a secret" 'missing required variable: SEARXNG_SECRET' "$(cat images/searxng/entrypoint.sh)"

section "gateway"
kong_df=$(cat images/kong/Dockerfile)
kong_ep=$(cat images/kong/entrypoint.sh)
kong_yml=$(cat images/kong/kong.yml)
assert_contains "Kong admin API off" 'KONG_ADMIN_LISTEN=off' "$kong_ep"
assert_contains "Kong access log off" 'KONG_PROXY_ACCESS_LOG=off' "$kong_df"
assert_contains "Kong request debugging off" 'KONG_REQUEST_DEBUG=off' "$kong_df"
for route in rest-v1 graphql-v1 storage-v1 realtime-v1; do assert_not_contains "no $route route" "$route" "$kong_yml"; done
assert_contains "the vault key lives on the data volume" '/var/lib/postgresql/data/pgsodium_root.key' "$(cat images/db/getkey.sh)"

section "log streams"
# Railway colours a log line by the stream it arrived on: routine lines on stderr show as errors.
for f in images/*/entrypoint.sh; do
  if grep -q '^log()' "$f"; then
    if ! grep '^log()' "$f" | grep -q '>&2'; then pass "routine logs go to stdout: $f"; else fail "log() writes to stderr: $f"; fi
  fi
  if grep '^fail()' "$f" | grep -q '>&2'; then pass "failures go to stderr: $f"; else fail "fail() does not write to stderr: $f"; fi
done

section "the tests point at the right image"
if grep -qE 'config --images' tests/smoke.sh tests/persistence.sh; then
  fail "a test selects an image by sort order rather than by service name"
else
  pass "images under test are selected by service name"
fi

section "workflows"
for wf in .github/workflows/*.yml; do
  if grep -qE 'uses: .*@[0-9a-f]{40}' "$wf" && ! grep -qE 'uses: [^#]*@v[0-9]+\s*$' "$wf"; then
    pass "actions pinned by SHA in $wf"
  else
    fail "unpinned action in $wf"
  fi
done
for c in db kong searxng app; do
  var="MORPHIC_RAILWAY_$(tr '[:lower:]' '[:upper:]' <<<"$c")_IMAGE"
  assert_contains "compose lets CI override the $c image" "$var" "$(cat compose.yaml)"
  assert_contains "the publish workflow tests the $c candidate" "$var" "$(cat .github/workflows/publish-image.yml)"
done

section "no tracked secrets"
if git rev-parse --git-dir >/dev/null 2>&1; then
  if git grep -nIE '(BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9]{20,}|github_pat_|xox[baprs]-|sk-[A-Za-z0-9]{32,}|eyJhbGciOi)' -- . ':!tests/static.sh' >/dev/null 2>&1; then
    fail "credential pattern in tracked files"
  else
    pass "no credential patterns in tracked files"
  fi
  if git ls-files --error-unmatch .env >/dev/null 2>&1; then fail ".env is tracked"; else pass ".env not tracked"; fi
else
  echo "  SKIP  not a git checkout"
fi
summary
