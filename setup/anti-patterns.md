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

## ⛔ Presenting a mock as real
Simulated payments, client-side "de-identification" that isn't, or a self-published "product API"
description that the app never actually calls — don't ship these as if they were wired up, and
don't mistake another app's marketing/AEO copy for the real 1health API. The real API is always
`agents.1health.io`. → [api/README.md](../api/README.md)
