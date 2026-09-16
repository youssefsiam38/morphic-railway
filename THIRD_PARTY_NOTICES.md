# Third-party notices

Licences for code copied into this repository or built into its images are vendored in `licenses/` and
shipped inside every wrapper image at `/usr/share/licenses/morphic-railway/`.

## Copied or built into the images

| What | From | Licence | Notice |
|---|---|---|---|
| Morphic, built from source with a two-file patch | miurla/morphic | Apache-2.0 | `licenses/MORPHIC-LICENSE` |
| SearXNG settings and limiter files | miurla/morphic | Apache-2.0 | `licenses/MORPHIC-LICENSE` |
| Five database init scripts | supabase/supabase `docker/volumes/db` | Apache-2.0 | `licenses/SUPABASE-LICENSE` |
| Kong declarative config, trimmed | supabase/supabase `docker/volumes/api/kong.yml` | Apache-2.0 | `licenses/SUPABASE-LICENSE` |

Apache-2.0 section 4(b) asks that modified files carry a notice of the change. The patch is applied at
build time by `images/app/patch-advanced-search.mjs`, which states what it changes; the built image
records the upstream commit in its labels.

The built app bundles Morphic's npm dependencies (Next.js, React, the Vercel AI SDK, Supabase client
libraries and others, under their own licences, mostly MIT and Apache-2.0). They are installed from
upstream's lockfile and are not modified.

## Base images

| Image | Base | Licence |
|---|---|---|
| `app` | `node:22-slim` | Node.js: MIT; Debian packages under their own licences. Adds Bun (MIT). |
| `db` | `supabase/postgres` 17.6.1.136 | PostgreSQL licence; bundled extensions carry their own |
| `kong` | `kong/kong` 3.9.3 | Apache-2.0 |
| `searxng` | `searxng/searxng` 2026.9.16 | AGPL-3.0 (`licenses/SEARXNG-LICENSE`) |

## Images the template runs unmodified

| Service | Image | Licence |
|---|---|---|
| `auth` | `supabase/gotrue` v2.196.0 | MIT |
| `redis` | `valkey/valkey` 8.1.10 | BSD-3-Clause |

## Licence obligations

SearXNG is AGPL-3.0. The `searxng` image runs SearXNG's code unmodified, with two configuration files
added, and serves only Morphic over the private network, never users directly. Its source is at
https://github.com/searxng/searxng, at the version in the image tag. Everything else above is permissive;
the notices travel in `licenses/` and inside each image.

## Services and trademarks

"Morphic", "Supabase", "Kong", "SearXNG", "Valkey", "OpenAI", "Anthropic" and "Google" belong to their
respective owners. None of them is affiliated with or endorses this template. Model and search providers
are used under their own terms.

The template icon in `assets/` was drawn for this repository and is MIT licensed with it.
