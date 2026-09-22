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
# Server-only secrets (LPL decryption) — from the app config/decrypt key you were given
ONEHEALTH_SECRET_KEY_DEMO=...        # required for demo
ONEHEALTH_SECRET_KEY_PROD=...        # required for prod
APP_ID_DEMO=...                      # your app's id in the demo environment
APP_ID_PROD=...                      # your app's id in prod

# App-owned customData namespace (safe to expose)
NEXT_PUBLIC_APP_ID=1                 # your appData.<appId> namespace key
```

## Bringing your prototype in

1. **Clone the template** and get it launching (auth page → demo login with your credentials).
2. **Drop the prototype's UI in** — components under `components/`, routes under `app/`. Keep the
   template's `app/api/token`, `app/auth`, `lib/auth-client.ts`, and `lib/api/` intact.
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
