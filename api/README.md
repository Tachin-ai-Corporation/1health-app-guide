# API reference — the tactical layer (live)

This guide teaches you **what pattern to use**. It deliberately does **not** copy the exact
request/response schema of all 474 routes — 1health already publishes those, auto-generated from
source on every pipeline run, at **agents.1health.io**. Copying them here would just go stale.

**Always confirm a call's exact contract in the live docs before you code it.**

## Where to look

| You want… | Fetch |
|---|---|
| Orientation (URL grammar, auth, error envelope, pagination, versions) | [`api/agents.md`](https://agents.1health.io/public/prod/api/agents.md) |
| The index of **every** route (single fetch) | [`api/manifest.md`](https://agents.1health.io/public/prod/api/manifest.md) |
| One route's exact contract | `…/api/<version>/<path>/agents.md` |
| Worked request/response examples for a route (when present) | `…/api/<version>/<path>/examples.md` |
| Cold-start: creds → token | [`api/authentication/agents.md`](https://agents.1health.io/public/prod/api/authentication/agents.md) |
| Machine index | [`llms.txt`](https://agents.1health.io/public/prod/llms.txt) |

Base for all of the above: `https://agents.1health.io/public/prod/`

## URL grammar (param-fold rule)

Path parameters are folded into filesystem-safe segments: a route parameter written `{name}` in
the OpenAPI spec becomes `_name_` in the doc URL. Curly braces never appear in a published URL.

```
route:  GET /v3/patient/{patientId}
doc:    https://agents.1health.io/public/prod/api/v3/patient/_patientId_/agents.md
```

Fold the **exact param name** from the route (`{patientId}` → `_patientId_`, not `_id_`), and note
that deeply nested item routes aren't all published individually — when a deep path 404s, fall back
to the [manifest](https://agents.1health.io/public/prod/api/manifest.md) and search for the route.
A collection and its item operations share one file. Every per-route `agents.md` uses the same
fixed section order: **Overview → Authorization → Path Parameters → Query Parameters → Request
Body → Responses → Example → Child Routes → Navigation.**

## Platform-wide facts worth caching

- **Real API host:** `https://app.1health.io/api` (prod) / `https://demo.1health.io/api` (demo).
  In app code, resolve it per call via `getOneHealthBaseUrl()` — don't hardcode.
- **Auth:** OAuth2 bearer token (see [setup/auth-and-launch.md](../setup/auth-and-launch.md)); the
  public client id is `public-client`.
- **Tenant scoping:** most resources are tenant-scoped — you see only your tenant's records.
- **Pagination:** zero-based `page`, `size` defaults to 50 — but param naming varies per endpoint
  (some also want `limit`); confirm per route.
- **Versions:** prefer the highest version exposing the resource. Coverage: v1 (44), v2 (353),
  v3 (49), unversioned (28). Grid/list lives in v3; most CRUD in v2.
- **Error envelope** is documented once, in the site guide — per-route pages list only their own
  trigger conditions.

## How to use it while coding

1. Have the type/verb in mind from the recipe.
2. Grep the **manifest** for the resource → open that route's `agents.md`.
3. Read Request Body + Responses; check `examples.md` if present.
4. Implement the call through `authFetch`/`callApi` (see the recipe's reference code).
