# Railway template configuration

The template's exact configuration. Reproduce it from this file if it ever has to be rebuilt.

| | |
|---|---|
| Name | Morphic + SearXNG |
| Code | `morphic-searxng` |
| Template id | `5d0518ca-a7ba-4ea3-a22f-778205614a1b` |
| Deploy URL | https://railway.com/deploy/morphic-searxng |
| Category | AI/ML |
| Card description | Perplexity-style AI answer engine with accounts and private SearXNG search |
| Icon | `assets/icon.png` |
| Overview markdown | `marketplace/OVERVIEW.md` (Railway enforces its section headings) |

Generated values use Railway's `secret()` function: `hexN` is `${{secret(N, "abcdef0123456789")}}` and `alnumN` is
`${{secret(N, "a-zA-Z0-9")}}` spelled out. Alphanumeric passwords are used wherever a value is embedded in a
connection URL, so nothing needs percent-encoding. Images are referenced by tag, because the template generator
rejects digests; `UPSTREAM.md` records the digests.

## Services

### `db`

| Field | Value |
|---|---|
| Source | `ghcr.io/youssefsiam38/morphic-railway-db:1.0.0` |
| Public domain | none |
| Volume | `/var/lib/postgresql/data` |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `POSTGRES_PASSWORD` | generated, alnum48 |

### `auth`

| Field | Value |
|---|---|
| Source | `supabase/gotrue:v2.196.0` |
| Public domain | none |
| Volume | none |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `JWT_SECRET` | generated, hex64 |
| `PORT` | `9999` |
| `GOTRUE_API_HOST` | `::` |
| `GOTRUE_API_PORT` | `9999` |
| `API_EXTERNAL_URL` | `https://${{kong.RAILWAY_PUBLIC_DOMAIN}}` |
| `GOTRUE_DB_DRIVER` | `postgres` |
| `GOTRUE_DB_DATABASE_URL` | `postgres://supabase_auth_admin:${{db.POSTGRES_PASSWORD}}@${{db.RAILWAY_PRIVATE_DOMAIN}}:5432/postgres` |
| `GOTRUE_SITE_URL` | `https://${{app.RAILWAY_PUBLIC_DOMAIN}}` |
| `GOTRUE_URI_ALLOW_LIST` | `https://${{app.RAILWAY_PUBLIC_DOMAIN}}/**` |
| `GOTRUE_DISABLE_SIGNUP` | `false` |
| `GOTRUE_JWT_ADMIN_ROLES` | `service_role` |
| `GOTRUE_JWT_AUD` | `authenticated` |
| `GOTRUE_JWT_DEFAULT_GROUP_NAME` | `authenticated` |
| `GOTRUE_JWT_EXP` | `3600` |
| `GOTRUE_JWT_SECRET` | `${{JWT_SECRET}}` |
| `GOTRUE_EXTERNAL_EMAIL_ENABLED` | `true` |
| `GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED` | `false` |
| `GOTRUE_EXTERNAL_PHONE_ENABLED` | `false` |
| `GOTRUE_MAILER_AUTOCONFIRM` | `true` |
| `GOTRUE_EXTERNAL_GOOGLE_REDIRECT_URI` | `https://${{kong.RAILWAY_PUBLIC_DOMAIN}}/auth/v1/callback` |
| `GOTRUE_EXTERNAL_GOOGLE_ENABLED` | optional, unset |
| `GOTRUE_EXTERNAL_GOOGLE_CLIENT_ID` | optional, unset |
| `GOTRUE_EXTERNAL_GOOGLE_SECRET` | optional, unset |
| `GOTRUE_SMTP_HOST` | optional, unset |
| `GOTRUE_SMTP_PORT` | optional, unset |
| `GOTRUE_SMTP_USER` | optional, unset |
| `GOTRUE_SMTP_PASS` | optional, unset |
| `GOTRUE_SMTP_ADMIN_EMAIL` | optional, unset |

### `kong`

| Field | Value |
|---|---|
| Source | `ghcr.io/youssefsiam38/morphic-railway-kong:1.0.0` |
| Public domain | target port 8000 |
| Volume | none |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `PORT` | `8000` |
| `JWT_SECRET` | `${{auth.JWT_SECRET}}` |
| `AUTH_HOST` | `${{auth.RAILWAY_PRIVATE_DOMAIN}}` |

### `searxng`

| Field | Value |
|---|---|
| Source | `ghcr.io/youssefsiam38/morphic-railway-searxng:1.0.0` |
| Public domain | none |
| Volume | none |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `SEARXNG_SECRET` | generated, hex64 |

### `redis`

| Field | Value |
|---|---|
| Source | `valkey/valkey:8.1.10-alpine` |
| Public domain | none |
| Volume | none |
| Start command | `sh -c 'exec valkey-server --requirepass "$REDIS_PASSWORD" --bind :: 0.0.0.0'` |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `REDIS_PASSWORD` | generated, alnum32 |

### `app`

| Field | Value |
|---|---|
| Source | `ghcr.io/youssefsiam38/morphic-railway-app:1.0.0` |
| Public domain | target port 3000 |
| Volume | none |
| Healthcheck | `/auth/login`, timeout from `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `PORT` | `3000` |
| `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` | `600` |
| `JWT_SECRET` | `${{auth.JWT_SECRET}}` |
| `DATABASE_URL` | `postgresql://postgres:${{db.POSTGRES_PASSWORD}}@${{db.RAILWAY_PRIVATE_DOMAIN}}:5432/morphic` |
| `SUPABASE_DB_URL` | `postgresql://postgres:${{db.POSTGRES_PASSWORD}}@${{db.RAILWAY_PRIVATE_DOMAIN}}:5432/postgres` |
| `SUPABASE_INTERNAL_URL` | `http://${{kong.RAILWAY_PRIVATE_DOMAIN}}:8000` |
| `NEXT_PUBLIC_SUPABASE_URL` | `https://${{kong.RAILWAY_PUBLIC_DOMAIN}}` |
| `SEARXNG_API_URL` | `http://${{searxng.RAILWAY_PRIVATE_DOMAIN}}:8080` |
| `LOCAL_REDIS_URL` | `redis://default:${{redis.REDIS_PASSWORD}}@${{redis.RAILWAY_PRIVATE_DOMAIN}}:6379` |
| `OWNER_EMAIL` | required input, no default |
| `OWNER_PASSWORD` | generated, alnum24 |
| `MORPHIC_SIGNUP_MODE` | `closed` |
| `OPENAI_API_KEY` | optional, unset |
| `ANTHROPIC_API_KEY` | optional, unset |
| `GOOGLE_GENERATIVE_AI_API_KEY` | optional, unset |
| `AI_GATEWAY_API_KEY` | optional, unset |
| `OPENAI_COMPATIBLE_API_KEY` | optional, unset |
| `OPENAI_COMPATIBLE_API_BASE_URL` | optional, unset |
| `OLLAMA_BASE_URL` | optional, unset |
| `MORPHIC_ALLOWED_SIGNUPS` | optional, unset |

## Notes

- **Service names are part of the configuration.** Every cross-service reference uses them.
- The template was generated from a skeleton project that was never deployed: the generator keeps only
  reference-valued variables, so every literal and generator was patched in afterwards with
  `templateChangeSetStage` (`TemplatePatch!`, `merge: true`) and `templateChangeSetApply`.
- **`redis` has a shell start command** because Railway does not expand variables in a start command:
  `valkey-server --requirepass ${REDIS_PASSWORD}` would set the password to that literal text.
- **The app's healthcheck is `/auth/login` with a 600-second timeout**; the first start creates the
  database and applies migrations before the server listens.
- `OWNER_EMAIL` has no default, so the deploy form asks for it. Headless:
  `railway deploy -t morphic-searxng -v "app.OWNER_EMAIL=you@example.com"`.
- Model provider keys and `MORPHIC_ALLOWED_SIGNUPS` are optional variables, not empty defaults, so the
  deploy succeeds before a provider is chosen; the app logs that no provider is configured.
- Clean-room verification included a temporary stand-in model service in the scratch project: a full chat
  called the search tool, SearXNG returned results over the private network, and Valkey cached them.
