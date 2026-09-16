# Marketplace audit

Checked 2026-09-16 against Railway's template search.

## Gap

| Existing template | Deploys | Why it does not cover this |
|---|---|---|
| "Morphic AI" (2024-09) | 6 | Upstream's repository with Redis and a Tavily key, from before Morphic needed PostgreSQL. Current Morphic cannot keep history without a database, has no sign-in without Supabase, and in anonymous mode lets every visitor chat on the deployer's keys. |
| "morphic [with openrouter]" (2024-11) | 2 | A fork's branch, same architecture and the same gaps. |
| Perplexica / Vane | 19, 9, 1 | A different answer engine. |
| SearXNG templates | up to 132 | Search engines only, no answers. |

## Why Morphic

- Apache-2.0.
- 9.1k stars and 2.3k forks; v1.7.0 released on 2026-09-16, 47 pull requests in the last 30 days.
- Supports every major model provider and OpenAI-compatible endpoints, and runs fully self-hosted with
  SearXNG.

## Why it needs a template rather than a raw repo deploy

1. **Sign-in needs Supabase and a rebuild.** Upstream's image runs anonymously; accounts need a Supabase
   project and an image built with its URL and key.
2. **Open signup.** Once sign-in works, anyone can create an account and chat on the deployer's keys.
3. **An open crawler.** `/api/advanced-search` runs searches and crawls pages for any caller.
4. **Five moving parts.** PostgreSQL, Supabase Auth, SearXNG with its settings file, Redis, and the app.

## Cost

Six services. The app (Next.js) and Postgres are the largest; Kong, GoTrue, SearXNG and Valkey are small.
Model calls are billed by the providers you configure.

## Category

**AI/ML**, beside the other AI search and chat templates.
