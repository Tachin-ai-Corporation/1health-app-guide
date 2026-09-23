# Link and unlink two instances

**Use when:** two instances already exist and you need to connect or disconnect them under a named
relationship — without a typed create-with-relationship call, and without recreating either
instance.
**Routes:** `POST /api/v2/relationship/create` → [agents.md](https://agents.1health.io/public/prod/api/v2/relationship/create/agents.md) · `DELETE /api/v2/relationship/delete` → [agents.md](https://agents.1health.io/public/prod/api/v2/relationship/delete/agents.md) · v1 fallback `POST /api/v1/boi/rel` + `DELETE /api/v1/boi/rel/{id}` → [agents.md](https://agents.1health.io/public/prod/api/v1/boi/rel/agents.md)
**Reference code:** none public — see the Minimal example
**Seen in:** 1health platform usage (behavior below confirmed against the demo environment)

## Pattern

1. **Resolve the relationship from the source type's schema** — `GET /api/v2/type/key/{typeKey}`
   lists its `relationships`, each with a `relKey` (used by v2) and a numeric `id` (used by v1).
   Never hand-type either ([schema-discovery.md](schema-discovery.md)).
2. **Link with v2**, one source to one or many targets:
   `{ fromInstanceId, toInstanceIds: [...], relKey, attributes: [] }`. **Always send `attributes`**,
   even as an empty array — omitting it returns a 500, although the docs mark it optional.
3. **Unlink with the same selector** — `fromInstanceId` + `toInstanceIds` + `relKey`.
4. **Don't trust v2's status — read back.** On demo, both create and delete returned a 400
   ("Transaction synchronization is not active") *while succeeding*: the edge was created, or removed.
   Decide the outcome by re-reading the relationship
   (`POST /api/v2/query/{typeKey}/{instanceId}?relKey=…&targetTypeKey=…`, see
   [choose-a-read-path.md](choose-a-read-path.md)), and never blind-retry a create.
5. **Drop to v1 when you need a status you can trust.** `POST /api/v1/boi/rel` with
   `{ fromBoInstanceId, toBoInstanceId, relTypeId }` links one pair, returns the new edge (with its
   own `id`), and answers a duplicate with a clean 400 ("already exists"). Delete that exact edge with
   `DELETE /api/v1/boi/rel/{id}`.

## Primary vs fallback

- **Primary — v2 by `relKey`:** link one instance to many targets in one call; send `attributes: []`
  and confirm by read-back.
- **Fallback — v1 (`/v1/boi/rel`):** when an automated flow must know per edge whether it worked, or
  you need the edge's id to remove exactly that edge. One pair per call; numeric `relTypeId`.

## Minimal example

```ts
import { callApi } from "@/lib/api"

// PRIMARY — v2, many targets per call. Read back instead of trusting the status.
async function linkInstances(typeKey: string, fromInstanceId: number, toInstanceIds: number[], relKey: string) {
  await callApi("relationship/create", "/api/v2/relationship/create", {
    method: "POST",
    body: JSON.stringify({ fromInstanceId, toInstanceIds, relKey, attributes: [] }), // attributes required
  })
  const res = await callApi<{ totalElements: number }>(
    "relationship/readBack",
    `/api/v2/query/${typeKey}/${fromInstanceId}?relKey=${encodeURIComponent(relKey)}&targetTypeKey=${typeKey}`,
    { method: "POST", body: JSON.stringify({ page: 0, size: 100 }) },
  )
  return (res.data?.totalElements ?? 0) > 0
}

// FALLBACK — v1 basement: one pair, a trustworthy status, and the edge id for a precise delete.
async function linkPairV1(fromBoInstanceId: number, toBoInstanceId: number, relTypeId: number) {
  const res = await callApi<{ id: number }>("boi/rel", "/api/v1/boi/rel", {
    method: "POST",
    body: JSON.stringify({ fromBoInstanceId, toBoInstanceId, relTypeId }),
  })
  return res.data?.id // 400 "already exists" on a duplicate
}

async function unlinkEdgeV1(edgeId: number) {
  return callApi("boi/relDelete", `/api/v1/boi/rel/${edgeId}`, { method: "DELETE" })
}
```

## Gotchas

- **v2 create 500s without `attributes`** — send `attributes: []` when there are no edge attributes.
- **v2 create/delete can return a 400 on success.** Treat the status as unknown and re-read; a
  retry after a "failed" create may just hit an edge that already exists.
- **Two identifiers for one relationship type:** v2 takes the string `relKey`; v1 takes the numeric
  relationship-type `id`. Both come from the same schema entry.
- One v2 call applies the same edge attributes to every target — if targets need different edge
  attribute values, make one call per distinct set.

## Related

- [relationship-path-building.md](relationship-path-building.md) — reading relationships back.
- [choose-a-read-path.md](choose-a-read-path.md) — the relationship-target endpoint used for read-back.
- [api-versions-and-layers.md](api-versions-and-layers.md) — when to drop to the v1 basement.
- [schema-discovery.md](schema-discovery.md)
