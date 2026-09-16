#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016  # single-quoted literals are matched, not expanded
# Persistence: data written before the containers are destroyed is there after they are recreated,
# and nothing the first boot does is repeated over it.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
umask 077

JWT='local-test-only-jwt-secret-000000000000000000000000000000'
OWNER_EMAIL='owner@example.com'
mint_keys "$JWT"
printf '%s' 'local-test-only-owner-password' > "$TEST_TMP/initial-pw"
printf '%s' "changed-in-the-app-$(date +%s)" > "$TEST_TMP/changed-pw"

section "stack up"
compose up -d --no-build >/dev/null
wait_for_code "$APP_URL/auth/login" 200 "$TEST_TIMEOUT" && pass "serving" || die "the app never became ready"

section "write state"
sign_in "$OWNER_EMAIL" "$TEST_TMP/initial-pw" "$TEST_TMP/token" && pass "owner signs in with the generated password" \
  || die "owner could not sign in with the initial password; run tests/smoke.sh first for a fresh stack"
code=$(http_code -X PUT "$GATEWAY_URL/auth/v1/user" -H "apikey: $(anon_key)" -H "Authorization: Bearer $(cat "$TEST_TMP/token")" \
  -H 'Content-Type: application/json' --data "$(jq -nc --rawfile p "$TEST_TMP/changed-pw" '{password:$p}')")
assert_eq "owner changes their password, as they would in the app" "200" "$code"
sign_in "$OWNER_EMAIL" "$TEST_TMP/changed-pw" "$TEST_TMP/token" || die "could not sign in with the changed password"
chat="persisted-chat-$(date +%s)"
assert_contains "the owner has a conversation" "Mock model answer" "$(chat_as "$TEST_TMP/token" "$chat" "Remember this conversation" | stream_text)"
saved=0
for _ in $(seq 1 20); do saved=$(psql_morphic "select count(*) from chats where id = '$chat'"); [ "$saved" = 1 ] && break; sleep 1; done
assert_eq "and it is saved" "1" "$saved"
probe="vault-probe-$(date +%s)"
psql_admin "select vault.create_secret('$probe', '$probe')" >/dev/null
assert_eq "a secret is stored in Supabase Vault" "1" "$(psql_admin "select count(*) from vault.decrypted_secrets where decrypted_secret = '$probe'")"

section "destroy and recreate every container (volumes kept)"
compose down >/dev/null
compose up -d --no-build >/dev/null
wait_for_code "$APP_URL/auth/login" 200 "$TEST_TIMEOUT" && pass "serving again" || die "the app did not come back"
logs=$(compose logs --no-color --no-log-prefix app)
assert_not_contains "Morphic's database is not created again" "created the morphic database" "$logs"
assert_contains "the owner bootstrap does not run again" "owner account exists from an earlier start" "$logs"

section "state survived"
sign_in "$OWNER_EMAIL" "$TEST_TMP/changed-pw" "$TEST_TMP/token2" && pass "the changed password still works" || fail "the changed password was lost"
sign_in "$OWNER_EMAIL" "$TEST_TMP/initial-pw" "$TEST_TMP/nothing" && fail "a redeploy reset the owner's password" || pass "a redeploy did not reset the owner's password"
assert_contains "the conversation is still in the owner's history" "$chat" "$(app_as "$TEST_TMP/token2" GET '/api/chats?offset=0&limit=20')"
assert_eq "Vault still decrypts with the key kept on the data volume" "1" "$(psql_admin "select count(*) from vault.decrypted_secrets where decrypted_secret = '$probe'")"
assert_eq "the signup gate is still in place" "t" "$(psql_admin "select exists(select 1 from pg_trigger where tgname = 'morphic_railway_gate_new_user')")"
printf '%s' 'someone-else-password-2' > "$TEST_TMP/other-pw"
assert_eq "and still refuses a stranger" "500" "$(sign_up another-stranger@example.com "$TEST_TMP/other-pw")"

section "the allowlist follows the variable"
cat > "$TEST_TMP/allow.override.yaml" <<YAML
services:
  app:
    environment:
      MORPHIC_ALLOWED_SIGNUPS: "@later.example.com"
YAML
docker compose -f "$REPO_ROOT/compose.yaml" -f "$TEST_TMP/allow.override.yaml" up -d --no-build app >/dev/null
wait_for_log app "signup: closed, 1 allowlist entry" 1 600 && pass "a changed allowlist is written on start" || fail "the allowlist was not rewritten"
wait_for_code "$APP_URL/auth/login" 200 300 || true
assert_eq "a newly allowed domain is admitted" "200" "$(sign_up joiner@later.example.com "$TEST_TMP/other-pw")"
printf '%s' 'someone-else-password-3' > "$TEST_TMP/other-pw3"
assert_eq "a removed entry no longer admits anyone" "500" "$(sign_up second@team.example.com "$TEST_TMP/other-pw3")"

section "operator password recovery"
printf '%s' "recovered-by-operator-$(date +%s)" > "$TEST_TMP/recovered-pw"
cat > "$TEST_TMP/reset.override.yaml" <<YAML
services:
  app:
    environment:
      OWNER_PASSWORD: $(cat "$TEST_TMP/recovered-pw")
      MORPHIC_RESET_OWNER_PASSWORD: "true"
YAML
docker compose -f "$REPO_ROOT/compose.yaml" -f "$TEST_TMP/reset.override.yaml" up -d --no-build app >/dev/null
wait_for_log app "owner password reset from OWNER_PASSWORD" 1 600 && pass "the reset is applied and the log says to remove the switch" || fail "no reset logged"
wait_for_code "$APP_URL/auth/login" 200 300 || true
sign_in "$OWNER_EMAIL" "$TEST_TMP/recovered-pw" "$TEST_TMP/token3" && pass "the owner signs in with the recovered password" || fail "recovered password refused"
compose up -d --no-build app >/dev/null
wait_for_log app "owner account exists from an earlier start" 1 600 && pass "without the switch, the owner is left alone again" || fail "the switch did not turn off"
summary
