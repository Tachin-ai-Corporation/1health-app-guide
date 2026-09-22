# Bulk tagging

**Use when:** you want to apply or remove reusable labels across many selected records in one user action — e.g. tagging a multi-select in a grid.
**Routes:** list via `POST /api/graphql` → [agents.md](https://agents.1health.io/public/prod/api/graphql/agents.md) (the `LabelTag` type) · apply via `PUT /api/v2/tag/journey?id=` → [route docs](https://agents.1health.io/public/prod/api/manifest.md) · remove via `PUT /api/v2/tag/remove?id=` → [agents.md](https://agents.1health.io/public/prod/api/v2/tag/remove/agents.md)
**Reference code:** [`lib/api/tags.ts`](https://github.com/Tachin-ai-Corporation/v0-trc-care-coordinator/blob/main/lib/api/tags.ts)
**Seen in:** trc-care-coordinator

## Pattern

1. Tags are their own queryable type (`LabelTag`), reached through the **GraphQL** read path rather than `/query` — list them filtered by target type and owning tenant.
2. Apply is scoped **per tag**: `PUT` the target record ids as a bare array to the tag's own apply endpoint (`?id={tagId}`). Applying several tags to the same selection is several calls — fan them out with `Promise.all`.
3. Remove uses a **different endpoint and a different body shape** (`{ instanceIds: [...] }`, not a bare array) — apply and remove are not mirror-image calls.
4. To show "tags common to every selected record" on a multi-select, compute it yourself: read each record's own tag relationships and intersect the sets client-side — there's no platform query for it.

## Minimal example

```ts
import { authFetch, getOneHealthBaseUrl } from "@/lib/auth-client"

interface Tag { id: number; name: string }

// LIST — via GraphQL, not /query. Scope by owning tenant.
async function fetchAllTags(tenantId: number): Promise<Tag[]> {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/graphql`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      query: `query ($filter: LabelTagFilterInput) {
        LabelTag(filter: $filter) { records { id, name } }
      }`,
      variables: { filter: { type: { equal: "Journey" }, createdByTenantId: { equal: tenantId } } },
    }),
  })
  if (!response.ok) return []
  const body = await response.json()
  return body?.data?.LabelTag?.records ?? []
}

// APPLY — one PUT per tag; body is a bare array of target ids.
async function applyTag(tagId: number, journeyIds: number[]): Promise<void> {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/v2/tag/journey?id=${tagId}`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(journeyIds),
  })
  if (!response.ok) throw new Error(`Apply tag ${tagId} failed: ${response.status}`)
}

// REMOVE — different endpoint, different body shape: { instanceIds }.
async function removeTag(tagId: number, journeyIds: number[]): Promise<void> {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/v2/tag/remove?id=${tagId}`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ instanceIds: journeyIds }),
  })
  if (!response.ok) throw new Error(`Remove tag ${tagId} failed: ${response.status}`)
}
```

## Gotchas

- Tags aren't reachable via `POST /query` in practice — `LabelTag` is read via `POST /api/graphql`, a third read path alongside `/query` and the grid family.
- Apply and remove use **different body shapes** for the same target-id list — copy-pasting one into the other silently sends the wrong shape.
- Apply is per-tag (`?id={tagId}` singular) — there's no "apply these N tags in one call."
- Scope the `LabelTag` list by `createdByTenantId` — tags are tenant-owned, and an unscoped read can surface another tenant's tags in a shared environment.
- There's no "tags common to all of these" query — intersect per-record tag sets client-side.

## Related

- [query-the-data-graph.md](query-the-data-graph.md) — GraphQL is a sibling read path; see its Gotchas re: "a third read path exists."
- [bulk-assignment.md](bulk-assignment.md) — another bulk grid action from the same app.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md).
