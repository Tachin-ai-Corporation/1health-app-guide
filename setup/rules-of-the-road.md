# Rules of the road

Read this once, top to bottom, before writing any code. It is the mental model plus the
constraints that make an app "1health-compliant." Everything else in this guide assumes it.

## The one architectural rule

**1health is the only backend — and the only datastore.** You are wiring a front-end prototype
directly to the 1health platform. There is no database to stand up, no ORM, no serverless data
layer, no third-party API for application data.

The *only* server-side code you write is one route, `/api/token`, whose sole job is to decrypt
the 1health **launch payload (LPL)** with your app secret and exchange it for OAuth tokens
(secrets must never reach the browser). After that, **every** read and write happens **client-side**
through `authFetch`, using the user's own token. See [auth-and-launch.md](auth-and-launch.md).

> **The precise rule: 1health is the only *datastore*, and `/api/token` is the only route that
> needs your app secret.** You *may* add other server routes — but only as **thin, stateless
> proxies**, and only for a reason the browser genuinely can't handle: hiding a secret, proxying a
> public API that blocks CORS (e.g. an NPI lookup), redacting PII before it reaches the client,
> sanitizing an upstream response/error, or streaming file bytes. Such a route **never persists
> application data anywhere but 1health.** The moment a route writes to a database, KV store, or a
> spreadsheet, you've broken the rule. See [conventions.md](conventions.md) and the
> [anti-patterns](anti-patterns.md) page.

## The 60-second data model

- **The platform is a typed object graph.** A **data-object type** is a PascalCase **string**
  (`"Person"`, `"Organization"`, `"WorkflowTemplate"`) — not a GUID. An **instance** is a numeric `id`.
- **Two read engines:** the generic `POST /api/v2/query` (flexible entity + relationship reads,
  RSQL filters) and the **grid** endpoints `POST /api/v3/health/grid/<view>` (pre-flattened list
  views). → [recipes/query-the-data-graph.md](../recipes/query-the-data-graph.md)
- **One write-extension mechanism:** every instance carries a schemaless `customData` JSON blob.
  → [recipes/read-write-custom-data.md](../recipes/read-write-custom-data.md)
- **The schema is introspectable** at runtime: list every type, and any type's attributes and
  relationships, from the API. You can build fully dynamic apps.
- **Workflows** are **Campaign → Template → Journey (instance) → Steps.** You advance a journey
  by *submitting its actionable step* — there is no "complete" verb.
- **Apps can self-provision:** find-or-clone a workflow template and create a campaign on a fresh
  tenant, by name — so your app installs its own workflow.

## The distinction that trips everyone up: "attribute" means two things

| | **Schema attribute** | **Dynamic step-field** |
|---|---|---|
| Used for | `/api/v2/query` projections & filters | workflow step form fields |
| Identifier | a plain **string** (`"birthDate"`) | a **GUID** (`fieldIdentifier`) |
| Where it comes from | discover via `/type/key` (or hardcode) | **fetched at runtime**, matched by `label` |
| Stable across envs? | **yes** | **NO — differs demo vs prod vs tenant** |

**Never hardcode a step-field GUID.** Resolve it by its stable `label` at runtime.

## Non-obvious constraints (the ones that cause bugs)

- **No general `DELETE`.** "Delete" is a flag in a POST/PUT body (`{ delete: true }`, `idsToUnset`)
  or omission-then-`REPLACE` for `customData`. (`/api/v2/file/{id}` is the rare real DELETE.)
- **`customData` APPEND is a shallow, top-level merge — it does NOT deep-merge.** A partial write
  under a nested/namespaced key replaces that whole subtree. Read → deep-merge client-side → write.
- **Query responses are prefixed:** root attrs come back as `ROOT.<Type>.<attr>`, related attrs as
  `<Edge>.<Target>.<attr>`. Use the extraction helpers; prefer suffix-matching.
- **`customData` may arrive as a JSON string**, not an object. Always parse defensively.
- **Version prefixes are not uniform:** mostly `v2`, grid/list is `v3`, GraphQL has none. Don't
  derive paths from a single version constant.
- **Timestamps often have no timezone** — treat as UTC (append `Z`) before parsing.
- **Pagination differs per endpoint** and `/api/v2/query` exposes no reliable total — detect the
  last page by a short page (`rows.length < pageSize`).
- **PHI belongs in the request body, never a URL/query string, a console log, or an error-reporting
  breadcrumb** — shape the call accordingly, not just where you persist the result.

Every recipe restates the gotchas relevant to it. The complete catalog lives in the app template's
[GOTCHAS.md](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/docs/api/GOTCHAS.md).

## Where the truth lives

- **This guide** = *how to think and what pattern to use.*
- **`agents.1health.io`** = *the exact, live request/response contract for each of 474 routes.*
  Always confirm a call's shape there before coding it. → [api/README.md](../api/README.md)
- **The app template** (`v0-1h-app-template`) = *the reference implementation in typed code.*
