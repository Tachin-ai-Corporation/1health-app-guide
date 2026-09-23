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
route:  GET /v3/patient/{patientId}/address
doc:    https://agents.1health.io/public/prod/api/v3/patient/_patientId_/address/agents.md
```

Fold the **exact param name** from the route (`{patientId}` → `_patientId_`, not `_id_`).

**Item routes are often documented on their collection's page, not a folded `/_param_/agents.md`
page of their own.** `GET /v3/patient/{patientId}` (get one patient) has no page at
`.../v3/patient/_patientId_/agents.md` — that URL is only a child-route index for the patient's
sub-resources. The route itself is documented on the collection page instead,
[`.../api/v3/patient/agents.md`](https://agents.1health.io/public/prod/api/v3/patient/agents.md),
alongside list/create/update/delete. A folded `/_param_/agents.md` URL you build by hand isn't
guaranteed to exist or to be the right page — before you trust one, check the resource's collection
page for a `## METHOD /path` heading, or fall back to the
[manifest](https://agents.1health.io/public/prod/api/manifest.md) and search for the route.
Every per-route `agents.md` uses the same fixed section order: **Overview → Authorization → Path
Parameters → Query Parameters → Request Body → Responses → Example → Child Routes → Navigation.**

## Routes without a published page yet

A handful of routes are supported for third-party apps but have no `agents.md` page yet. A recipe
that teaches one flags it with a `⚠ Not yet in 1health's published API docs` banner and shows the
route in backticks with no link — test it against demo before you rely on it.

## Platform-wide facts worth caching

- **Real API host:** `https://app.1health.io/api` (prod) / `https://demo.1health.io/api` (demo).
  In app code, resolve it per call via `getOneHealthBaseUrl()` — don't hardcode.
- **Auth:** OAuth2 bearer token (see [setup/auth-and-launch.md](../setup/auth-and-launch.md)); the
  public client id is `public-client`.
- **Tenant scoping:** most resources are tenant-scoped — you see only your tenant's records.
- **Pagination:** zero-based `page`, `size` defaults to 50 — but param naming varies per endpoint
  (some also want `limit`); confirm per route.
- **Versions:** prefer the highest version exposing the resource. Coverage: v1 (44), v2 (353),
  v3 (49), unversioned (28). Grid/list lives in v3; most CRUD in v2. Choosing between layers when
  more than one could work → [recipes/api-versions-and-layers.md](../recipes/api-versions-and-layers.md).
- **Error envelope** is documented once, in the site guide — per-route pages list only their own
  trigger conditions.

## How to use it while coding

1. Have the type/verb in mind from the recipe.
2. Grep the **manifest** for the resource → open that route's `agents.md`.
3. Read Request Body + Responses; check `examples.md` if present.
4. Implement the call through `authFetch`/`callApi` (see the recipe's reference code).
