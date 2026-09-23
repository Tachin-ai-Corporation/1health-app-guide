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

## 6. Where server data lives

- **SWR stays the default** (§3) for fetching and caching 1health reads.
- **A query-cache library (e.g. TanStack Query) is an equivalent lane**, not a downgrade — reach for
  it in a larger app that already wants its richer devtools, mutation/invalidation helpers, or finer
  per-query stale/GC tuning. Don't run both in the same app for the same data.
- **One-off calls** (a single component's own fetch-on-mount, nothing else needs the result) may use
  a plain `useEffect` + `AbortController`, aborted in its cleanup — no library needed for a read
  nothing else shares.
- **Never use Redux (or any global store) as a server-data cache.** A store is fine for session/tenant
  identity and UI flags (which credential is active, a spinner/overlay state) — it should never hold
  a fetched 1health record. Invalidate the cache/effect that owns the data instead of copying it into
  a store "for convenience."

## 7. API layers

1health's REST surface has three layers, not three interchangeable versions of the same thing: v1 is
low-level primitives, v2 is the everyday wrapper API, and v3 wraps v2 (or is a fresh API of its own —
grids, patient, user-management…). Start at the highest layer that covers the job and drop a layer
only when the wrapper above it doesn't expose what you need.
→ [api-versions-and-layers.md](../recipes/api-versions-and-layers.md)
