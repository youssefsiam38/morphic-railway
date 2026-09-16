# Upstream provenance

Everything the bundle runs, where it comes from, and what this repository changes. Digests are
multi-architecture index digests as resolved on 2026-09-16. The Railway template references tags,
because Railway's template generator rejects digest references; the Dockerfiles and `compose.yaml` pin
tag and digest.

## Morphic

| | |
|---|---|
| Project | https://github.com/miurla/morphic |
| Licence | Apache-2.0 (`licenses/MORPHIC-LICENSE`) |
| Release pinned | `v1.7.0`, commit `514c8cc562ada40f5f0cafddfd9cb9874cd6c01c` |
| Published image | `ghcr.io/miurla/morphic`, built without Supabase (anonymous mode only), so not used |
| Stack | Next.js 16 (`next start`), Drizzle on PostgreSQL, Supabase Auth, SearXNG, Redis |

The source is fetched by commit id, so git verifies the content, and built the way upstream's own
Dockerfile builds it: Node 22, `bun install` (here with `--frozen-lockfile`), `next build`, and the same
files copied into the runtime image.

What `images/app/Dockerfile` changes relative to upstream's Dockerfile:

- **Build-time values.** `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` are built as
  placeholders and written with real values at start-up (`fill-public-env.mjs`).
- **One behaviour patch** (`patch-advanced-search.mjs`): `/api/advanced-search` answers only the app's own
  search tool. The build fails unless both edits match exactly once.
- **Added at runtime:** this repository's entrypoint, `railway-db.mjs` (uses the `postgres` client from
  Morphic's own dependencies), `gate.sql`, `bootstrap-owner.mjs`, `fill-public-env.mjs` and the key minter.
- The server runs `next start -H ::` instead of `-H 0.0.0.0`, and as the image's `node` user.

| Base | Image | Digest |
|---|---|---|
| Node.js | `node:22-slim` | `sha256:83f487e0a63425e5b4d146fb5e5be574bcbe1b7b843d3ebafdd95eaf7767a7e5` |
| Bun | npm `bun@1.4.2` | installed with npm, as upstream does, at a pinned version |

## SearXNG

| | |
|---|---|
| Image | `searxng/searxng:2026.9.16-f725cc793`, `sha256:c6239076c5e36720765d1a7815af3e660e0fcf49239a2e3b161b5477c9cd82b0` |
| Licence | AGPL-3.0 (`licenses/SEARXNG-LICENSE`) |
| Copied files | Morphic's `searxng-settings.yml` and `searxng-limiter.toml`, into `images/searxng/` |

The wrapper bakes in those two files and refuses to start without `SEARXNG_SECRET`. SearXNG's code is not
modified.

## Supabase self-hosting stack

| | |
|---|---|
| Source | https://github.com/supabase/supabase/tree/master/docker, commit `e693f206f5050b0004a86e12e533bb75ba2a9c76` |
| Licence | Apache-2.0 (`licenses/SUPABASE-LICENSE`) |
| Copied files | `volumes/db/{realtime,_supabase,webhooks,roles,jwt}.sql` into `images/db/init/`; `volumes/api/kong.yml`, trimmed to Auth, into `images/kong/kong.yml` |

The `db` and `kong` wrappers are shared with the Kortix, wacrm and DeskcommCRM Railway templates
(https://github.com/youssefsiam38/kortix-railway).

| Component | Image | Digest | Licence | Wrapped |
|---|---|---|---|---|
| Postgres | `supabase/postgres:17.6.1.136` | `sha256:f371b5f3f2ac0a05703f33d6e6134515fb2498cab708fb948a0aeb7481467c00` | PostgreSQL | `db` |
| Auth | `supabase/gotrue:v2.196.0` | `sha256:c0c25187a6b835e65a6f6e6c6b39d090e832d40e6de5186f2c038e0411944232` | MIT | no |
| Kong | `kong/kong:3.9.3` | `sha256:9a2ae6699a2ce0d60592eb176555d3594a22782c20cc6557a61ff3a7e8b559a3` | Apache-2.0 | `kong` |

## Valkey

`valkey/valkey:8.1.10-alpine`, `sha256:d2e18f3410b6f616de1417f570fa55261af2898b9c5b2cfb6781ce2373ea43d1`,
BSD-3-Clause, unmodified. Upstream's compose file uses `redis:alpine`; Valkey speaks the same protocol
under a permissive licence.

## Published images

`ghcr.io/youssefsiam38/morphic-railway-{db,kong,searxng,app}`, `1.0.0`, amd64, built and tested together by
`.github/workflows/publish-image.yml`. Each ships this repository's licence set at
`/usr/share/licenses/morphic-railway/`.
