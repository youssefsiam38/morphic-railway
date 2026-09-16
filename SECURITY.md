# Security

## Reporting

Open an issue at https://github.com/youssefsiam38/morphic-railway/issues for a problem with the template
or its wrappers. Report anything in Morphic itself to https://github.com/miurla/morphic. Do not include
credentials, API keys, cookies or public hostnames in an issue.

## What this bundle holds

Every question users asked and every answer, with the sources Morphic read, their notes, and their
accounts. The model provider keys sit in the `app` service's variables. Access to an account is the
ability to run searches and model calls on those keys.

## Problems this template closes

| Problem on a public platform | What the template does |
|---|---|
| Upstream's Docker image runs in anonymous mode: everyone who reaches the domain shares one account and chats on the deployer's model keys | Sign-in through a bundled Supabase Auth; the wrapper refuses `ENABLE_AUTH=false`. Guest chat stays off. |
| With Supabase Auth, anyone can sign up: the sign-up page is linked from the sign-in page, and the gateway takes signups directly | A `BEFORE INSERT` trigger on `auth.users` admits only the owner and the addresses and domains in `MORPHIC_ALLOWED_SIGNUPS`, including Google sign-ins. |
| `POST /api/advanced-search` is unauthenticated: anyone can make the instance run SearXNG searches and crawl pages for them | A build-time patch makes the route answer 404 unless the request carries a random per-process token that only Morphic's own search tool sends. |
| The search tool reaches that route through a base URL taken from the request's `Host` header | `BASE_URL` is pinned to the local listener, so a forged header cannot redirect the call. |
| Supabase's `.env.example` ships a working JWT secret and database password; SearXNG's settings carry a placeholder secret | Every secret is generated per deploy; the wrappers refuse example values and short ones. |
| Valkey without a password on a shared network | `--requirepass` from a generated password, expanded by a shell because Railway does not expand start commands. |
| A redeploy re-running a "create owner" step would reset the owner's password | The bootstrap does nothing once the `OWNER_EMAIL` account exists. |
| Kong's admin API, access log and request-debug token; routes to services that do not exist | Off; Kong routes Supabase Auth only. |

## What is exposed

| Surface | Anonymous | Notes |
|---|---|---|
| `app` domain | Home page, sign-in and sign-up pages, and conversations their owners made public with Share | Chat, history, notes and uploads require a session. `/api/advanced-search` answers 404. |
| `kong` domain, no API key | 401 | |
| `kong` domain, anon key | Supabase Auth: sign-in, sign-up (gated), password recovery | The anon key is public by design: it is in the browser bundle. Nothing else is routed. |
| `searxng`, `redis`, `db`, `auth` | Not public | Private network only. SearXNG serves JSON only. |

The service-role key never reaches the browser; `tests/smoke.sh` checks every browser chunk for it.

## How the signup gate decides

A new user is admitted when one of these holds, and refused otherwise:

1. **Owner bootstrap.** The app wrapper stores the SHA-256 of 32 random bytes; the owner bootstrap sends
   those bytes as user metadata through the Auth admin API over the private network; the insert deletes
   the hash. The nonce is never logged, never leaves the container, and cannot be replayed.
2. **Allowlist.** The address, or `@` and its domain, is in `MORPHIC_ALLOWED_SIGNUPS`. The match is exact:
   `@example.com` does not admit `someone@sub.example.com` or `someone@evilexample.com`.
3. **Open mode.** `MORPHIC_SIGNUP_MODE=open`, set deliberately.

The mode and the allowlist are rewritten from the variables on every start, so removing an entry and
redeploying closes it again. The nonce is never kept in `auth.users`: a second trigger removes it on the
update Supabase Auth makes right after the insert. `tests/smoke.sh` signs up a stranger, a forged nonce
and a look-alike domain and checks that none of them created a user.

## Residual risks

**The allowlist admits by address.** E-mail addresses are not verified until SMTP is configured
(`GOTRUE_MAILER_AUTOCONFIRM=true`), so someone who knows an allowlisted address can sign up as it first.
Every address at an allowlisted domain can sign up. Configure SMTP on `auth` with autoconfirm off if that
matters to you.

**Every user spends your keys.** Morphic's per-user usage budgets and rate limits belong to its hosted
service (`MORPHIC_CLOUD_DEPLOYMENT`, Upstash) and are off here. Admit only people you trust with the bill.

**Outbound requests.** Answers are built from pages Morphic fetches on the users' behalf. Upstream's
`safeFetch` refuses private, loopback, link-local and unique-local addresses, checked when connecting, so
the fetch tool cannot reach Railway's private network; leave `FETCH_ALLOW_PRIVATE_NETWORK` unset. The
search tool's call to SearXNG and to the app itself are the only private requests, and neither takes a
URL from the user.

**A refused signup looks like a server error.** Supabase Auth reports any trigger exception as "Database
error saving new user" (HTTP 500).

**Anyone with access to the Railway project has everything.** Project variables contain the database
password, the JWT secret (from which the service-role key follows) and your model keys. Treat project
membership as root on the instance.

**Legacy HS256 API keys with a 2035 expiry.** Rotating them means rotating `JWT_SECRET` on `auth` and
redeploying `kong` and `app`; all sessions end.

**The Vault root key** is a file on the `db` volume, beside the data it protects, because Railway gives a
service one volume.

## Secrets

| Secret | Generated on | Referenced by | Purpose |
|---|---|---|---|
| `POSTGRES_PASSWORD` | `db` | auth, app | Password of the Supabase database roles |
| `JWT_SECRET` | `auth` | kong, app | Signs sessions and the Supabase API keys |
| `SEARXNG_SECRET` | `searxng` | | SearXNG's own secret key |
| `REDIS_PASSWORD` | `redis` | app | Valkey's password |
| `OWNER_PASSWORD` | `app` | | The owner's first password |
| Model and search provider keys | entered by you | | On `app` |

The per-process token for the advanced-search route is generated by the entrypoint on every start and is
never a variable. No wrapper prints a secret; the owner's e-mail is masked in the log. `tests/smoke.sh`
searches every service's log for every test secret and the service-role key.

## Recovering the owner account

Set a new `OWNER_PASSWORD` and `MORPHIC_RESET_OWNER_PASSWORD=true` on `app` and redeploy. The start applies
the password to the `OWNER_EMAIL` account and logs a warning to remove the switch. Remove it, or every
redeploy resets the password again.
