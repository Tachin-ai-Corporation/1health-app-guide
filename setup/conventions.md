# Conventions — the decisions that shape every recipe

These are the house rules. When two example apps disagreed, this is the lane the guide picks.
Recipes assume you follow these.

## 1. Server routes: one secret route + thin proxies only

**1health is the only datastore.** `/api/token` is the only route that needs your app secret.
You may add other server routes, but only as **thin, stateless proxies**, and only for a reason
the browser can't handle:

| Legit reason for a server route | Example |
|---|---|
| Hide a secret / service token | a privileged lookup, a partner API key |
| Proxy a public API that blocks CORS | NPI registry, ICD-10, openFDA |
| Redact PII before it reaches the client | obfuscate contact info unless partnered |
| Sanitize an upstream response or error | normalize a shape, reword a raw error |
| Stream file bytes / set headers | inline-PDF download proxy |

A proxy **never persists application data** anywhere but 1health. A route that writes to Postgres,
a KV store, or a Google Sheet has broken the rule — see [anti-patterns.md](anti-patterns.md).

## 2. Communications: use 1health-native email & SMS

Send email through `POST /api/v2/email/send` and SMS through `POST /api/v2/twilio/send`, on the
signed-in user's token. **Send exactly the documented DTO fields** — an extra/guessed field can
drive the backend into a 500. Do **not** wire in SendGrid, Twilio-direct, or another mailer unless
you have a concrete reason 1health's endpoints can't meet; a third-party mailer is a deviation, not
the default. → [native-email-and-sms.md](../recipes/native-email-and-sms.md)

## 3. Data fetching: SWR by default

Fetch 1health data through **SWR**. React Strict Mode double-invokes effects in dev; a raw
`useEffect` + `fetch` fires every request twice, and SWR dedupes concurrent requests to the same
key. If your app doesn't use SWR, the acceptable fallback is an explicit in-flight/`hasLoaded`
ref-guard (and a promise-memo `Map` for keyed lookups) — but SWR is the recommended lane.

## 4. Storing app data: two mechanisms

| Mechanism | Use when |
|---|---|
| **Schemaless `customData` blob** (default) | app-specific fields, bookkeeping, config, UI state — anything you don't need the platform to validate. → [read-write-custom-data.md](../recipes/read-write-custom-data.md) |
| **Admin-defined typed custom fields** (`/v3/custom-data/definition`) | you need named, typed, platform-validated fields with a defined schema per business-object class. → [typed-custom-field-definitions.md](../recipes/typed-custom-field-definitions.md) |

**Per-user state:** durable or cross-device state → the user's own `Person` `customData`; per-viewer
convenience that needn't survive a device change (last filter, a collapsed panel, an unsent draft)
→ `localStorage` is fine. → [per-user-preferences.md](../recipes/per-user-preferences.md)

## 5. Identity: user token by default; service key is advanced

Default: every call runs as the **signed-in user** (`authFetch`, their bearer). Some apps need a
privileged **service key** for operations a user's token is refused (cross-tenant reads, unauthenticated
onboarding writes). That **split-identity** architecture is powerful but security-heavy — treat it as
an **advanced, guardrailed** option (enforce which operations may use the key; re-authorize every
request server-side; never leak the token). → [split-identity-service-key.md](../recipes/split-identity-service-key.md),
[server-side-authorization.md](../recipes/server-side-authorization.md)
