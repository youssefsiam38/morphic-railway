# Deploy and Host Morphic on Railway

Morphic is an open-source AI answer engine in the style of Perplexity. Ask a question and it searches the
web, reads the sources and writes a cited answer, rendered with a generative UI of images, grids and
headings, with quick and adaptive search modes and a model picker for every provider you configure. This
is a community-maintained template; it is not affiliated with the Morphic project.

## About Hosting Morphic

Morphic is a Next.js app with a PostgreSQL database, Supabase Auth for accounts, SearXNG for search and
Redis for caching. Upstream's Docker image runs in anonymous mode, one shared account meant for a single
person on their own machine; real accounts need a Supabase project and an image rebuilt with its keys.

This template runs everything on Railway instead, in one project: Morphic with accounts and history, a
self-hosted Supabase Auth with its gateway, Postgres, SearXNG and Valkey, six services in all, with no
Supabase account and no search API key. The first start creates the database, applies Morphic's
migrations, creates your owner account from the e-mail you enter, writes this deployment's sign-in
settings into the built app, and only then starts serving.

It also closes what a public deployment leaves open. Signup is closed by default and enforced in the
database, so only you and the addresses or domains you list get accounts on your model keys. And
Morphic's advanced-search route, which runs searches and crawls pages for any caller, answers only
Morphic's own search tool.

## Why Deploy Morphic on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your
infrastructure so you don't have to deal with configuration, while allowing you to vertically and
horizontally scale it.

By deploying Morphic on Railway, you are one step closer to supporting a complete full-stack application
with minimal burden. Host your servers, databases, AI agents, and more on Railway.

Concretely, this template generates every secret the bundle needs, derives Supabase's API keys from one of
them, gives the app and the sign-in gateway public HTTPS domains, keeps SearXNG, Valkey and the database on
Railway's private network with dual-stack listeners, and attaches a volume to the database.

## Common Use Cases

- A private Perplexity-style search for yourself or your team, on your own model keys.
- Research with cited sources and a searchable history, kept in a database you control.
- Try different models side by side: OpenAI, Anthropic, Google, Ollama or any OpenAI-compatible provider.
- Share individual answers publicly while everything else stays private.

## Dependencies for Morphic Hosting

- At least one model provider key: OpenAI, Anthropic, Google, Vercel AI Gateway, an OpenAI-compatible
  provider such as OpenRouter, or an Ollama server.
- Optional: SMTP settings for password-reset e-mails, a Google OAuth client for Google sign-in, and
  S3-compatible storage for file upload.
- Nothing else. No Supabase account and no search API key.

### Deployment Dependencies

- Morphic: https://github.com/miurla/morphic (Apache-2.0)
- SearXNG: https://github.com/searxng/searxng (AGPL-3.0)
- Supabase Auth: https://github.com/supabase/auth (MIT)
- Template repository, images and tests: https://github.com/youssefsiam38/morphic-railway

### Implementation Details

The app image is built from Morphic's pinned release with placeholder values that the start-up replaces,
and one change: the advanced-search route requires a random per-process token that only Morphic's own
search tool sends. Thin wrappers adapt Supabase and SearXNG to Railway: init scripts and settings baked in
where their compose files would mount them, API keys minted from the shared JWT secret with byte-identical
output in Node and Perl, and the Vault key kept on the database volume. Every service refuses to start on
missing, short or published example secrets. The bundle is tested as a whole in CI, including a full chat
against a stand-in model, on fresh and reused volumes, before any image is pushed.

The deploy form asks for one value, `OWNER_EMAIL`. After deploying, set a model key such as
`OPENAI_API_KEY` on the app service, copy `OWNER_PASSWORD` from its variables, and sign in on the app's
domain. To let others in, list their addresses or domains in `MORPHIC_ALLOWED_SIGNUPS`.
