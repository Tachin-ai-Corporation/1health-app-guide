# Anti-patterns — do NOT do these

Real things found in production 1health apps that you must **not** copy. Each is followed by the
compliant alternative. If you catch yourself reaching for one of these, stop.

## ⛔ Any non-1health datastore
Some apps persisted app data outside 1health: a **Postgres** database (via an ORM), **Google
Sheets** webhooks for lead/telemetry capture, and a bespoke **n8n automation tier** on a
1health-looking hostname that is *not* the real API.

**Why it's wrong:** it breaks the one rule that makes an app portable and compliant — 1health is
the only datastore. It splits your source of truth, escapes tenant scoping and audit, and can leak
PHI outside the platform's controls.

**Instead:** store app data in `customData` (schemaless) or typed custom fields; store durable
per-user state on the user's own `Person`; keep records as first-class 1health instances. See
[conventions.md](conventions.md) §1 and §4.

## ⛔ Using `localStorage`/IndexedDB as a datastore
Fine for **per-viewer convenience** (last-used filter, a collapsed panel, an unsent draft). **Not**
for shared/business data, and not for per-user state that must survive a device change — that
belongs in `Person` `customData`. → [per-user-preferences.md](../recipes/per-user-preferences.md)

## ⛔ A third-party mailer (SendGrid, etc.) as the default
1health exposes native email and SMS. Reach for a third-party mailer only with a concrete reason
the native endpoints can't meet — otherwise it's an unnecessary extra backend and secret to manage.
→ [native-email-and-sms.md](../recipes/native-email-and-sms.md)

## ⛔ Hardcoding environment-specific ids or GUIDs
Campaign, template, step, role, application, and tenant ids — and dynamic step-field
`fieldIdentifier` GUIDs — **differ across demo/prod and across tenants**. Hardcoding one is a
deploy-time landmine. Discover them at runtime (schema discovery, resolve step-fields by `label`,
find campaigns/templates by name). → [rules-of-the-road.md](rules-of-the-road.md),
[schema-discovery.md](../recipes/schema-discovery.md)

## ⛔ Hardcoding step names or step-field GUIDs in submit logic
Brittle to any template redesign and non-portable across environments. Resolve the actionable step
structurally and resolve fields by `label`. → [resolve-actionable-step.md](../recipes/resolve-actionable-step.md),
[dynamic-step-fields.md](../recipes/dynamic-step-fields.md)

## ⛔ Calling a 1health endpoint without `authFetch`
Skipping the Bearer token / auto-refresh (e.g. posting to an automation webhook unauthenticated)
works only by an unguessable URL and skips the platform's auth. Route every 1health call through
`authFetch`/`callApi`. A genuine automation webhook is the rare, explicit exception — not a habit.

## ⛔ A sign-in shortcut that skips the launch exchange
Examples: a mock session, a hard-coded or pasted access token, a "skip auth" flag, or writing a
token into cookies by hand so a local build "just works."

**Why it's wrong:** you're testing a flow production never runs. It skips the decrypt, the code
exchange, and the user's real permissions, and shortcuts like these tend to ship.

**Instead:** add the QA sign-in branch to `/api/token`. It mints a real launch payload with a QA
user's API key and runs the normal exchange. → [qa-and-local-testing.md](qa-and-local-testing.md)

## ⛔ QA only as an admin
Testing every screen with your own System Admin account.

**Why it's wrong:** an admin is allowed nearly everything, so every permission bug stays hidden until
a manager or an employee hits a `403` in production.

**Instead:** run the QA checklist as all three roles (System Admin, Manager, Employee) from a demo
QA org, testing the denied actions as well as the allowed ones.
→ [qa-and-local-testing.md](qa-and-local-testing.md)

## ⛔ QA keys on the production deployment (or in the repo)
This covers three mistakes:
- setting `ONEHEALTH_QA_KEY_*` in the production deployment's env settings;
- committing them (`.env`, `.env.production`, an example file with real values);
- exposing them as `NEXT_PUBLIC_*`.

**Why it's wrong:** a QA key is a live credential for a QA user. On production, one misconfiguration
could sign strangers in as that user. Committed, or in `NEXT_PUBLIC_*`, anyone can read it.

**Instead:** keep QA keys in `.env.local`, or in a dev/stage deployment's settings only. The QA
branch also refuses to run in production builds, as a backstop.
→ [qa-and-local-testing.md](qa-and-local-testing.md)

## ⛔ A shared, instance-wide cancel token
Wiring one cancellation token onto every request from a client instance — so cancelling it aborts
every in-flight call sharing that instance at once — is legacy plumbing, not a real cancellation
strategy; it's easy to end up with one nobody ever actually calls `.cancel()` on.

**Instead:** give every request its own `AbortController`, created by the caller and torn down in
its own cleanup (an effect unmount, a superseded search, a closed dialog).
→ [resilient-api-client.md](../recipes/resilient-api-client.md)

## ⛔ Turning credentials off per call instead of using a bare client
A per-call flag that just skips attaching the bearer on your normal authenticated client is not a
safe way to make an unauthenticated call — that client's shared `401` handler is still wired up, so
a stray non-2xx on the "opted-out" call can still trigger a token refresh or a forced logout.

**Instead:** route any call that doesn't need a session through a genuinely separate client with no
interceptors at all — no bearer, no `401`→refresh→logout handling, a short timeout.
→ [resilient-api-client.md](../recipes/resilient-api-client.md)

## ⛔ PHI in URLs, query strings, console logs, or error-reporting breadcrumbs
A `GET` with patient-identifying data in the query string — or a stray `console.log`, or a value
carried into an error-tracker breadcrumb — puts PHI somewhere server logs, proxies, browser history,
and third-party tooling can all see, even when your actual datastore is fully compliant.

**Instead:** shape the request so anything patient-identifying travels in a POST/PUT body, and scrub
error-reporting payloads before they leave the browser. → [rules-of-the-road.md](rules-of-the-road.md)

## ⛔ Kicking off an async bulk-export job and polling it to completion
Grid/report export-and-poll jobs are unreliable — a builder-owned export shouldn't depend on one
ever finishing.

**Instead:** page through `/query` with an offset loop and filter/shape the rows client-side.
→ [bulk-read-and-export.md](../recipes/bulk-read-and-export.md)

## ⛔ Redux (or any global store) as a server-data cache
Copying a fetched 1health record into Redux/a global store "so any component can read it" duplicates
the cache your data-fetching layer already maintains — and nothing keeps the two in sync after a
write.

**Instead:** keep server data in SWR/a query-cache hook (or a one-off effect); reserve a global store
for session/tenant identity and UI flags only. → [conventions.md](conventions.md) §6

## ⛔ Presenting a mock as real
Simulated payments, client-side "de-identification" that isn't, or a self-published "product API"
description that the app never actually calls — don't ship these as if they were wired up, and
don't mistake another app's marketing/AEO copy for the real 1health API. The real API is always
`agents.1health.io`. → [api/README.md](../api/README.md)
