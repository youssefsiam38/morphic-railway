# Morphic on Railway

A community Railway template for [Morphic][upstream], the open-source AI answer engine: ask a question,
and it searches the web, reads the sources and writes a cited answer with a generative UI. It is not
affiliated with the Morphic project.

Upstream's Docker setup runs Morphic in **anonymous mode**: one shared account for everyone who reaches it,
meant for a single person on their own machine. Real sign-in needs a Supabase project and an image rebuilt
with its keys. This template runs **all of it on Railway, in one project**: Morphic with accounts and
history, a self-hosted Supabase Auth, its own Postgres, SearXNG for search, and Valkey for the search
cache. No Supabase account and no search API key.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/morphic-searxng)

## What you get

- **Six services wired over Railway's private network**, every secret generated at deploy time. Two are
  public: Morphic, and the Supabase Auth gateway the browser signs in through.
- **Accounts, not anonymous mode.** Every conversation belongs to a signed-in user; strangers cannot chat
  on your model keys.
- **An owner account before anyone can reach the app**, created from the e-mail you enter and a generated
  password.
- **Signup closed by default, enforced in the database.** Supabase Auth accepts any signup on its own;
  this template admits only the owner and the addresses or domains you list, however the signup arrives.
- **Search included.** SearXNG runs privately beside Morphic, so search needs no Tavily or other key.
- **A closed back door.** Upstream's `/api/advanced-search` route runs searches and crawls pages for
  anyone who calls it. Here it answers only Morphic's own search tool.
- Migrations applied on start, an image built from a pinned upstream release, and the whole bundle
  tested in CI, including a chat against a stand-in model, before any image is pushed.

## First run

1. Deploy the template and enter `OWNER_EMAIL`, the address you will sign in with.
2. Set at least one model provider key on the `app` service (for example `OPENAI_API_KEY` or
   `ANTHROPIC_API_KEY`) and redeploy it. Morphic lists the models each configured provider offers.
3. Copy `OWNER_PASSWORD` from the `app` service's **Variables** tab and sign in on the app's domain.
   Morphic has no password setting in its menus; to change the password, open `/auth/update-password`
   on the app's domain while signed in.
4. To let others in, list their addresses or whole domains in `MORPHIC_ALLOWED_SIGNUPS` (for example
   `friend@example.com,@yourcompany.com`) and redeploy `app`. They sign up on the app's sign-up page.

## Services

| Service | What it is | Image | Public | Volume |
|---|---|---|---|---|
| `app` | Morphic | `ghcr.io/youssefsiam38/morphic-railway-app` | yes | |
| `kong` | Supabase API gateway, Auth only | `ghcr.io/youssefsiam38/morphic-railway-kong` | yes | |
| `auth` | Supabase Auth (GoTrue) | `supabase/gotrue` | | |
| `db` | Supabase Postgres | `ghcr.io/youssefsiam38/morphic-railway-db` | | `/var/lib/postgresql/data` |
| `searxng` | SearXNG, JSON only | `ghcr.io/youssefsiam38/morphic-railway-searxng` | | |
| `redis` | Valkey, search cache | `valkey/valkey` | | |

See `ARCHITECTURE.md` for how the pieces fit together.

## Variables you may want to change

All on the `app` service unless noted.

| Variable | Default | Meaning |
|---|---|---|
| `OWNER_EMAIL` | asked at deploy | The owner account's e-mail. |
| `OWNER_PASSWORD` | generated | The owner's first password. Read on the first start only. |
| `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_GENERATIVE_AI_API_KEY`, `AI_GATEWAY_API_KEY` | unset | Model providers. Set at least one. |
| `OPENAI_COMPATIBLE_API_KEY`, `OPENAI_COMPATIBLE_API_BASE_URL`, `OPENAI_COMPATIBLE_MODELS` | unset | Any OpenAI-compatible provider (OpenRouter, DeepSeek and others). |
| `OLLAMA_BASE_URL` | unset | An Ollama server the app can reach. |
| `MORPHIC_ALLOWED_SIGNUPS` | empty | Comma-separated addresses and `@domain` entries that may sign up. |
| `MORPHIC_SIGNUP_MODE` | `closed` | `open` lets anyone sign up and chat on your keys. |
| `MORPHIC_RESET_OWNER_PASSWORD` | unset | Set `true` with a new `OWNER_PASSWORD` to recover the owner; remove afterwards. |
| `SEARCH_API` | `searxng` | `tavily`, `exa` or `firecrawl` with their keys, instead of the bundled SearXNG. |
| `GOTRUE_EXTERNAL_GOOGLE_*` (`auth`) | unset | Google sign-in; see below. |
| `GOTRUE_SMTP_*` (`auth`) | unset | SMTP for password-reset e-mails. |

Morphic's other settings (`SEARXNG_*` tuning, `BRAVE_SEARCH_API_KEY`, `JINA_API_KEY`, file upload with
`R2_*`/`S3_ENDPOINT`, Langfuse tracing) pass through unchanged; see upstream's `docs/CONFIGURATION.md`.

### Google sign-in

Morphic's sign-in page has a Google button. To make it work, create a Google OAuth client with the
redirect URI `https://` + the `kong` domain + `/auth/v1/callback`, then set on `auth`:
`GOTRUE_EXTERNAL_GOOGLE_ENABLED=true`, `GOTRUE_EXTERNAL_GOOGLE_CLIENT_ID`,
`GOTRUE_EXTERNAL_GOOGLE_SECRET`. The template already sets `GOTRUE_EXTERNAL_GOOGLE_REDIRECT_URI`. Google
accounts pass the same signup rules as everyone else.

## Persistent data

| Service | Path | Holds | If lost |
|---|---|---|---|
| `db` | `/var/lib/postgresql/data` | Users, conversations, sources, notes, and the Vault root key | Everything |

SearXNG and Valkey hold nothing that matters: the cache refills itself.

## Before you rely on it

- **You bring the model.** Morphic calls the providers you configure, billed to your keys. Every
  signed-in user chats on them.
- **File upload is off** until you configure S3-compatible storage (`R2_*`, or `S3_ENDPOINT` for another
  provider), as upstream's own Docker setup.
- **SearXNG queries public search engines from Railway's IP addresses.** Engines may rate-limit or
  challenge them; switch `SEARCH_API` to a paid provider if results dry up.
- **No e-mail is sent until you configure SMTP on `auth`.** Accounts are created confirmed; the sign-up
  page still says to check your e-mail, and the new account can simply sign in. Use
  `MORPHIC_RESET_OWNER_PASSWORD` to recover the owner.
- A refused signup shows Supabase's generic "Database error saving new user". The refusal is deliberate;
  see `SECURITY.md`.

## Local development

```bash
docker compose build
tests/static.sh
tests/smoke.sh
tests/persistence.sh
```

The compose file mirrors the Railway services one-to-one with fixed, public, local-test-only secrets, plus
a stand-in model provider that exists only for the tests. The app is served on `http://localhost:13700`
and the gateway on `http://kong.localhost:18700`; move them with `MORPHIC_TEST_PORT` and
`MORPHIC_TEST_GATEWAY_PORT`.

After deploying:

```bash
tests/railway-smoke.sh https://<app-domain> https://<kong-domain>
```

## Documents

| File | Contents |
|---|---|
| `ARCHITECTURE.md` | Service graph, build-time values, start-up, the signup gate, search |
| `SECURITY.md` | Threat model, what is exposed, residual risks |
| `RAILWAY_TEMPLATE.md` | The exact template configuration |
| `UPSTREAM.md` | Pinned versions, digests, and what this repository changes |
| `MAINTENANCE.md` | Release process, bumping upstream, rollback |
| `MARKETPLACE_AUDIT.md` | Why this template exists |
| `THIRD_PARTY_NOTICES.md` | Licences |

## Licence

MIT for this repository. Morphic is Apache-2.0; the Supabase components are MIT, Apache-2.0 and the
PostgreSQL licence; SearXNG is AGPL-3.0 and runs unmodified apart from its settings file. See
`THIRD_PARTY_NOTICES.md`.

[upstream]: https://github.com/miurla/morphic
