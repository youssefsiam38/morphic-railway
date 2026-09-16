# Maintenance

## Release process

1. Make the change on a branch. The `test` workflow builds every image and runs the full suite on every
   push and pull request.
2. Run locally:
   ```bash
   docker compose build --pull
   tests/static.sh && tests/smoke.sh && tests/persistence.sh
   ```
3. Tag `vX.Y.Z`. The `publish-image` workflow builds all four images as local candidates, runs the smoke
   and persistence suites against the whole bundle of candidates, and only then retags and pushes those
   exact images to GHCR as `X.Y.Z`, `X.Y` and `latest`.
4. Update the Railway template (id in `RAILWAY_TEMPLATE.md`): the image tags of `app`, `kong`, `db` and
   `searxng`, with `templateChangeSetStage` then `templateChangeSetApply`. Tags only; the generator rejects
   digests. Republish the overview with
   `railway templates update <id> --readme-file marketplace/OVERVIEW.md` if it changed. Never put
   angle-bracket placeholders in the overview: Railway strips them.
5. Deploy the updated template into a scratch project, set a model key, run
   `CHAT=1 tests/railway-smoke.sh https://<app> https://<kong>` with `OWNER_EMAIL` and
   `OWNER_PASSWORD_FILE`, then delete the scratch project.

The four images are versioned together, so the template never mixes wrapper versions.

## Bumping Morphic

1. Read the release notes and the commits between the pinned release and the candidate.
2. Change `ARG MORPHIC_COMMIT` (and `MORPHIC_VERSION`) in `images/app/Dockerfile`.
3. Build. The build fails, by design, if:
   - `patch-advanced-search.mjs` no longer matches the search tool's call or the route's handler;
   - no built file carries a placeholder, or the server bundle lacks the patch.
4. Run the suites. New migrations are applied on the next start of existing deployments.
5. Check the list below.

### Breaking-change checklist

- [ ] New `NEXT_PUBLIC_*` variables (`grep -rhoE 'NEXT_PUBLIC_[A-Z_]+' app lib components hooks`): each
      needs a placeholder or a fixed build value.
- [ ] `ENABLE_AUTH`, `ENABLE_GUEST_CHAT` and `getCurrentUserId` still mean what the entrypoint assumes.
- [ ] New routes under `app/api/`: does each check the user, or does it need the same treatment as
      `advanced-search`?
- [ ] `getBaseUrlString` is still the only user of `BASE_URL`.
- [ ] Sign-in is still Supabase Auth only (a new provider would still be gated, but may need GoTrue
      settings).
- [ ] `lib/db/migrate.ts` and `drizzle/` still exist where the entrypoint runs them.
- [ ] Upstream's `searxng-settings.yml` changed: copy it again, keeping the header comment.
- [ ] Upstream's `.env.local.example` gained required variables.

## Bumping SearXNG, Valkey and the Supabase stack

SearXNG publishes a dated tag per commit; move to a newer one when there is a reason (engine breakage is
common). Keep the Supabase stack in step with the Kortix and wacrm templates, which share the `db` and
`kong` wrappers, and record commits and digests in `UPSTREAM.md`.

## What to watch

| Source | Why |
|---|---|
| https://github.com/miurla/morphic/releases | New versions, migrations and variables. |
| Morphic `docs/CONFIGURATION.md` and `.env.local.example` | Settings and their defaults. |
| https://github.com/searxng/searxng/commits/master | Engine fixes when results dry up. |
| https://github.com/supabase/auth/releases | Supabase Auth changes. |

## Rolling back

Republish the template with the previous image tags. **The database does not roll back**: migrations a
newer image applied stay applied. Restore the `db` volume from a backup taken before the upgrade if the
older app cannot run on the newer schema.

## Backups

Railway volume backups cover `db`. It holds the Vault root key file next to the cluster; restore them
together.

## If this repository is abandoned

Everything here is small: one Dockerfile and a handful of scripts for Morphic, three thin wrappers, and
the tests. Fork it, change the image `source` labels and GHCR paths, and publish your own template.
