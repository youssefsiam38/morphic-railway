# Architecture

## Service graph

```
                   browser                                   model providers, search engines, web pages
        ┌─────────────┴─────────────┐                                   ▲
   https (app)              https (kong)                                │
        │                          │                                    │
       app ────────────────────────│────────────────────────────────────┘
      │ │ │ │                     kong ──▶ auth ──┐
      │ │ │ └─ Supabase Auth calls ─▶ kong          │
      │ │ └─── search ─▶ searxng ───────────────────│───▶ public search engines
      │ └───── search cache ─▶ redis                │
      └─────── Morphic data, migrations, gate ─▶ db ◀┘
```

Two services are public: `app`, and `kong`, because Morphic's browser code signs in through Supabase Auth
directly. Everything else is reachable only on Railway's private network at `<service>.railway.internal`.

Morphic uses Supabase for sign-in only; its data is in its own Postgres tables through Drizzle. So the
bundle runs Supabase Auth and the Kong gateway (trimmed to Auth routes) but not PostgREST, Storage,
Realtime or Studio. Supabase's Postgres image is still used, because Supabase Auth's migrations expect its
roles, and one database server holds both: Supabase Auth in the `postgres` database, Morphic in a
`morphic` database of its own.

## Wrappers and the build

| Service | Image | Why |
|---|---|---|
| `app` | built here | Upstream's image is built without Supabase, so it can only run anonymously. |
| `db` | wrapper | Supabase's init scripts baked in (no bind mounts on Railway); the Vault root key moved onto the data volume. |
| `kong` | wrapper | Its config is baked in, and the API keys it checks are minted from `JWT_SECRET`. |
| `searxng` | wrapper | Morphic's settings file baked in; the secret must come from a variable. |
| `auth`, `redis` | upstream | Unchanged; `redis` gets its password through a shell start command. |

The `db` and `kong` wrappers are the same as in the Kortix, wacrm and DeskcommCRM Railway templates, with
Kong trimmed to Auth.

## Build-time values

Next.js inlines every `NEXT_PUBLIC_*` variable into the server and browser bundles when the app is built.
Upstream therefore asks you to rebuild with your Supabase URL and key. A template cannot: the gateway's
domain does not exist until the template is deployed, and the key is signed with a secret generated at
the same moment.

So the image is built once, in CI, from upstream's release commit, with placeholder values:

| Variable | Placeholder |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | `https://morphic-railway-placeholder-supabase-url.invalid` |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | `morphic-railway-placeholder-supabase-publishable-key` |

The build records every output file that contains one and keeps a pristine copy of each. On every start,
`fill-public-env.mjs` rewrites those files from their pristine copies with the deployment's real values.
The values must match strict shapes (a bare origin, a three-part JWT), so nothing can break out of the
JavaScript string it lands in, and the start fails if any placeholder is left anywhere.

Browsers cache the built JavaScript by file name. If the gateway domain ever changes, users need a hard
reload once.

## The advanced-search patch

Morphic's search tool does not call SearXNG directly for deep searches. It calls the app's own
`POST /api/advanced-search`, which searches, crawls the result pages and caches the result in Redis. That
route has no authentication, so on a public domain anyone can use it.

`patch-advanced-search.mjs` changes two upstream files at build time, and the build fails unless each
edit matches exactly once:

- the search tool's call sends the header `x-morphic-railway-internal` with `MORPHIC_RAILWAY_INTERNAL_TOKEN`;
- the route compares that header with the variable in constant time and answers 404 on any mismatch, or
  when the token is shorter than 32 characters.

The entrypoint generates the token (32 random bytes, hex) on every start and exports it to the server
process only. The search tool finds the route through `BASE_URL`, which upstream otherwise derives from
the request's `Host` header; the entrypoint pins it to `http://127.0.0.1:$PORT`.

## Start-up

Railway starts every service at once, so each waits for what it needs.

1. `db` initialises the cluster and runs Supabase's init scripts.
2. `auth` runs its own migrations, creating the `auth` schema.
3. `app` validates its variables, mints the Supabase keys, waits for the database and for Auth to answer
   through Kong.
4. `app` creates the `morphic` database if it does not exist and runs upstream's migration script
   (`bun run lib/db/migrate.ts`, Drizzle), as upstream's own image does. A failure stops the start.
5. `app` applies `gate.sql`, writes the signup policy, creates the owner, writes the public values into
   the build, and only then starts `next start` on `[::]`.

## The owner

`bootstrap-owner.mjs` creates `OWNER_EMAIL` (e-mail confirmed) through Supabase Auth's admin API over the
private network. Morphic keeps no extra user record, so nothing else is needed. The claim is "the
`OWNER_EMAIL` account exists"; once it does, the bootstrap exits without touching it, so a redeploy never
undoes a password change. Recovery is an explicit switch, `MORPHIC_RESET_OWNER_PASSWORD`.

## The signup gate

`gate.sql` puts the rule where every path to a new user converges, a `BEFORE INSERT` trigger on
`auth.users`, in the `postgres` database. A new user is admitted when:

1. their metadata carries the **one-time bootstrap nonce**. The entrypoint generates 32 random bytes,
   stores only their SHA-256 in `morphic_railway.settings`, and passes the nonce to the owner bootstrap.
   The insert consumes the hash; the entrypoint also deletes it afterwards whatever happened.
2. `morphic_railway.settings.signup_mode` is `open`;
3. the lower-cased address, or `@` and its domain, is in `morphic_railway.signup_allowlist`.

The wrapper rewrites the mode and the allowlist from `MORPHIC_SIGNUP_MODE` and `MORPHIC_ALLOWED_SIGNUPS` in
one transaction on every start. A second trigger, `BEFORE UPDATE`, removes the nonce from stored
metadata, because Supabase Auth rewrites the metadata right after the insert.

## Search

`SEARCH_API` defaults to `searxng`. SearXNG runs Morphic's own settings file: JSON output only, limiter
off, no public instance features. It listens on `[::]:8080` (the image's Granian defaults), private only.
Valkey caches advanced-search results; Morphic works without it but reconnects on every search, so it is
part of the bundle as in upstream's compose file. It has no volume: losing the cache costs nothing.

## Networking

Railway's private DNS answers with IPv6 (and IPv4 in newer environments), and clients like Kong prefer
IPv6, so every listener is dual-stack: Next.js with `-H ::`, Kong on both families, GoTrue on `::`,
SearXNG on `::`, Valkey bound to `::` and `0.0.0.0`. The local test network has IPv6 enabled so a listener
that only answers on IPv4 fails the tests, not a deploy.

## Logs

Routine lines go to stdout and failures to stderr, because Railway colours a line by its stream. The
migration script's output is kept out of the log unless it fails. Kong's access log and request-debug
feature are off. Morphic itself logs some warnings on stderr (for example Langfuse's "no exporter
configured" when tracing is not set up); they are upstream's and harmless.
