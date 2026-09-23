# Scaffolding: start from the template

Don't start from an empty Next.js app. Start from **`v0-1h-app-template`** — it already ships the
auth flow, the `authFetch`/`callApi` layer, typed modules for every core engine, a session
context, and the design system. You bring the prototype's screens; the template brings 1health.

Repo: https://github.com/Tachin-ai-Corporation/v0-1h-app-template

## What the template gives you (don't rebuild these)

```
app/
  api/token/route.tsx     # the ONE server route: LPL decrypt + token exchange
  auth/                   # launch/auth page with environment selection
  page.tsx                # auth guard → renders app or redirects to /auth
lib/
  auth-client.ts          # authFetch(), refreshToken(), cookie + base-url helpers
  api/
    client.ts             # callApi / callApiRaw / ApiResponse envelope
    config.ts             # endpoint path builders + RECORD_TYPES / ATTRIBUTES (fill per app)
    query.ts              # /api/v2/query + RSQL builders + response extractors
    grid.ts               # /api/v3/health/grid/* list views + fetch-all pagination
    schema.ts             # runtime type/attribute/relationship discovery (+ cache)
    custom-data.ts        # read/append/replace/merge/delete customData
    workflow-template.ts  # campaign→template resolution + field-by-label
    journey.ts            # journeys: create/fetch/list/status/assign
    journey-step.ts       # steps: fetch + the 3 submit recipes + metadata builder
    attachments.ts        # journey files: upload/download/delete
    comments.ts           # journey comments
    campaign.ts           # campaign lifecycle: create/activate/share/list/find
    workflow-provisioning.ts  # self-bootstrap: find/clone/publish + ensureWorkflow()
    user.ts / tenant.ts   # current user + tenant/org config
contexts/
  session-context.tsx     # useSession() — cached user + tenant, fetched once
docs/                     # the source docs these recipes are distilled from
```

## Required environment variables

Set these server-side (e.g. `.env.local`, or your host's env settings). **Never** prefix the
secret keys with `NEXT_PUBLIC_`.

```bash
# Server-only secrets (LPL decryption) — from YOUR OWN registered 1health app
# (see setup/auth-and-launch.md § "Provision your own app"; this guide ships no keys)
ONEHEALTH_SECRET_KEY_DEMO=...        # required for demo
ONEHEALTH_SECRET_KEY_PROD=...        # required for prod
APP_ID_DEMO=...                      # your app's id in the demo environment
APP_ID_PROD=...                      # your app's id in prod

# App-owned customData namespace (safe to expose)
NEXT_PUBLIC_APP_ID=1                 # your appData.<appId> namespace key
```

**QA keys are the exception to "your host's env settings".** They go in `.env.local`, or in a
dev/stage deployment's settings, but never the production deployment's and never with a
`NEXT_PUBLIC_` prefix. See [qa-and-local-testing.md](qa-and-local-testing.md).

```bash
# QA sign-in: .env.local, or a dev/stage deployment ONLY. Never production. Never committed.
ONEHEALTH_QA_KEY_SYSADMIN=...        # API key of your demo QA org's System Admin user
ONEHEALTH_QA_KEY_MANAGER=...         # API key of its Manager user
ONEHEALTH_QA_KEY_EMPLOYEE=...        # API key of its Employee user
# APP_STAGE=staging                  # deployed dev/stage builds only: turns QA sign-in on there
```

## Bringing your prototype in

1. **Clone the template** and get it signing in on demo. Locally, that means adding the QA sign-in
   branch and signing in as each QA role ([qa-launch-with-api-key.md](../recipes/qa-launch-with-api-key.md)).
2. **Drop the prototype's UI in** — components under `components/`, routes under `app/`. Keep the
   template's `app/api/token`, `app/auth`, `lib/auth-client.ts`, and `lib/api/` intact. The QA
   sign-in branch is an addition to those files, not a rewrite.
3. **Delete the prototype's mock data layer.** Every place it read/wrote mock data becomes a call
   through `lib/api/*` (see the [Recipe Index](../recipes/INDEX.md)).
4. **Fill `lib/api/config.ts`** with your app's real type names (`RECORD_TYPES`) and the few schema
   attributes you use — or discover them at runtime via `schema.ts`.
5. **Namespace your app data** under `appData.<NEXT_PUBLIC_APP_ID>` in `customData`.
6. **Wire data fetching with SWR** (the template's required pattern) so React Strict Mode doesn't
   double-fire requests.

Then work screen-by-screen using [prototype-to-app.md](prototype-to-app.md).

## Don't

- Don't add a database, Prisma/Drizzle, Supabase, or any non-1health data store.
- Don't add auth libraries (NextAuth, Clerk, …) — auth is the LPL flow, already built.
- Don't call the API with raw `fetch`, and don't cache the base URL.
- Don't put QA keys on the production deployment, in the repo, or in `NEXT_PUBLIC_*`.
