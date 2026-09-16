#!/bin/sh
# morphic-railway SearXNG entrypoint: refuse to start without a real secret, then hand over to upstream.
set -eu
fail() { printf '[morphic-searxng] FATAL: %s\n' "$*" >&2; exit 1; }

[ -n "${SEARXNG_SECRET:-}" ] || fail "missing required variable: SEARXNG_SECRET"
[ "${#SEARXNG_SECRET}" -ge 32 ] || fail "SEARXNG_SECRET must be at least 32 characters"
case "$SEARXNG_SECRET" in ultrasecretkey|ursecretkey) fail "SEARXNG_SECRET is a published example value" ;; esac

printf '[morphic-searxng] private search backend on [::]:%s, JSON only\n' "${GRANIAN_PORT:-8080}"
exec /usr/local/searxng/entrypoint.sh "$@"
