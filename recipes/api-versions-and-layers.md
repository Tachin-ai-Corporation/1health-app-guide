# Choose the right API layer (v1, v2, v3)

**Use when:** more than one version could plausibly do the job — you're about to call an endpoint,
or the manifest shows the same resource at two versions, and you need to pick.
**Routes:** n/a — a decision about which layer to call, not one endpoint. Worked examples below
link the specific routes.
**Reference code:** none public — see the Minimal example.
**Seen in:** 1health platform usage

## Pattern

1. Think in **layers**, not eras. **v1 is the basement** — low-level primitives directly over the
   object graph (raw instance/relationship/attribute access, e.g. `boi`). **v2 is the standard
   wrapper layer over v1** — the everyday typed API most calls belong to, including the general read
   engine (`POST /api/v2/query`) and the `customData` extension point
   (`POST /api/v2/data/custom-data/bulk`). **v3 wraps v2, or is a fresh API of its own** — grids/list
   views (`POST /api/v3/health/grid/...`), the patient API, user-management, public register/OTP,
   and other surfaces that didn't exist at v2.
2. **Start at the highest layer that covers the job.** Search the manifest for your resource across
   all three versions before you write a call — don't assume the version you found first, or the one
   an old example used, is the only one that exists.
3. **Drop a layer only when the layer above doesn't expose what you need.** A field with no typed
   route anywhere forces a v1 raw attribute write — see
   [boi-instance-attribute-write.md](boi-instance-attribute-write.md). Most day-to-day CRUD, queries,
   and app-data storage never need to leave v2.
4. **Not every v2 route has a v3 sibling, and not every v3 route wraps a v2 one.** v3 is a separate,
   smaller namespace, not a wholesale upgrade of v2 — never assume a pair exists in either direction;
   confirm in the manifest.
5. **When both a v2 and a v3 route exist for the same resource, prefer v3** — e.g.
   [`GET /api/v3/user-management/user/{id}`](https://agents.1health.io/public/prod/api/v3/user-management/user/agents.md)
   over the deprecated
   [`GET /api/v2/user/{id}`](https://agents.1health.io/public/prod/api/v2/user/agents.md). Heed a
   "deprecated" note wherever the docs or manifest carry one.
6. **Never call v1 "legacy" or "deprecated."** It's a different layer, not an older version of v2/v3
   — plenty of v1 primitives have no v2/v3 equivalent at all and are the correct, permanent tool for
   that job.
7. GraphQL and the grid family sit alongside this ladder, not inside it: GraphQL carries no version
   segment at all, and grids are v3-only with no v1/v2 equivalent to fall back to.

## Primary vs fallback

- **Primary — the highest layer that covers the job:** v3 when the resource has a v3 surface
  (grids, patient, user-management, public register/OTP, …), otherwise v2. This is almost always
  what you want, and what the rest of this guide's recipes call.
- **Fallback — drop one layer:** only once you've confirmed, in the manifest, that the layer above
  genuinely doesn't expose the field or operation you need (a raw attribute with no typed route, a
  relationship shape only v1 models). Dropping to v1 is a deliberate, occasional escape hatch, not a
  starting point.

## Minimal example

```ts
import { callApi } from "@/lib/api"

// Prefer the highest layer that covers the job — v3 is a newer, more specific surface:
const user = await callApi("user/getById", `/api/v3/user-management/user/${userId}`)

// v2 is the everyday API — general queries and customData live here, with no v3 alternative:
const orgs = await callApi("query/orgs", "/api/v2/query", {
  method: "POST",
  body: JSON.stringify({ key: "Organization", attributes: ["id", "name"] }),
})

// v1 is the basement: raw attribute access with no typed wrapper above it. Drop here only once
// you've confirmed no v2/v3 route exposes the field — see boi-instance-attribute-write.md.
const raw = await callApi("boi/read", `/api/v1/boi/${instanceId}?dataView=full`)
```

## Gotchas

- A 404 at the version you tried doesn't mean the resource doesn't exist — grep the manifest across
  all three versions before concluding you need a different layer.
- v3 is not a drop-in replacement namespace for v2 — most v2 CRUD has no v3 sibling; only reach for
  v3 in the specific families the platform actually put there.
- "Deprecated" describes a specific superseded route (like the v2/v3 user example), never v1 as a
  whole — a v1 primitive with no wrapper anywhere is still the right call, permanently.
- GraphQL and the grid family aren't part of this ladder — don't look for a "v1 GraphQL," and don't
  expect every grid view to have a `/query` equivalent or vice versa.

## Related

- [../api/README.md](../api/README.md) — how to search the manifest and read a route's doc page.
- [boi-instance-attribute-write.md](boi-instance-attribute-write.md) — the concrete v1 escape hatch.
- [query-the-data-graph.md](query-the-data-graph.md) and [grid-list-views.md](grid-list-views.md) —
  the v2 and v3 read engines this ladder chooses between.
- [read-write-custom-data.md](read-write-custom-data.md) — v2's schemaless extension point.
- Concepts: [../setup/conventions.md](../setup/conventions.md).
