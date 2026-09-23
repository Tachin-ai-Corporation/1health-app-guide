# Bulk tagging

**Use when:** you want to apply or remove reusable labels across many selected records in one user action — e.g. tagging a multi-select in a grid.
**Routes:** list via `POST /api/graphql` → [agents.md](https://agents.1health.io/public/prod/api/graphql/agents.md) (the `LabelTag` type) · fallback listing via `POST /api/v3/health/grid/label-tag` (not yet in the published docs) · apply/create-or-apply via `PUT /api/v2/tag/_key_` (not yet in the published docs) · remove via `PUT /api/v2/tag/remove` → [agents.md](https://agents.1health.io/public/prod/api/v2/tag/remove/agents.md) · tag details via `GET /api/v2/tag/_id_/details` (not yet in the published docs) · merge via `POST /api/v2/tag/_id_/migrate` (not yet in the published docs)
**Reference code:** [`lib/api/tags.ts`](https://github.com/Tachin-ai-Corporation/v0-trc-care-coordinator/blob/main/lib/api/tags.ts)
**Seen in:** trc-care-coordinator · 1health platform usage (create-or-apply, merge, grid listing)

> **⚠ Not yet in 1health's published API docs:** `PUT /api/v2/tag/{key}`, `GET /api/v2/tag/{id}/details`,
> `POST /api/v2/tag/{id}/migrate`, `POST /api/v3/health/grid/label-tag`. 1health supports these for
> third-party apps, but agents.1health.io has no page for them yet — the shapes shown here come from
> working apps. Test them against demo before you rely on them.

## Pattern

1. Tags are their own queryable type (`LabelTag`), reached through the **GraphQL** read path rather than `/query` — list them filtered by target type and owning tenant.
2. Apply is scoped **per tag**: `PUT` the target record ids as a bare array to the tag's own apply endpoint (`?id={tagId}`). Applying several tags to the same selection is several calls — fan them out with `Promise.all`.
3. Remove uses a **different endpoint and a different body shape** (`{ instanceIds: [...] }`, not a bare array) — apply and remove are not mirror-image calls.
4. To show "tags common to every selected record" on a multi-select, compute it yourself: read each record's own tag relationships and intersect the sets client-side — there's no platform query for it.
5. The apply endpoint doubles as **create-or-apply**: pass an existing tag's numeric id (`?id=`) to
   apply it, or omit `id` and pass `?name=` with a brand-new name to create the tag and apply it in
   the same call — handy for a picker that lets someone type a new tag without a separate create
   round trip.
6. To fold one tag into another (cleaning up near-duplicate tags), use the dedicated merge endpoint
   instead of re-tagging every instance by hand — it moves every instance already carrying the
   source tag onto the target tag, and can optionally deactivate the source tag in the same call.
7. For an admin-facing tag management table (sortable/searchable/paginated) rather than a lightweight
   picker, list tags through the grid engine's `label-tag` view instead of GraphQL — same underlying
   data, different ergonomics; see [grid-list-views.md](grid-list-views.md).

## Primary vs fallback

- **Primary — GraphQL `LabelTag`:** the default for a lightweight tag picker's option list — cheap,
  flexible filtering by target type/tenant.
- **Fallback — the grid engine's `label-tag` view:** switch to this for an admin-facing tag
  management screen that needs the grid's own sort/search/pagination ergonomics over the same data.

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

// CREATE-OR-APPLY — `key` names the TARGET TYPE being tagged (e.g. "journey"),
// not the tag. Pass an existing tag id, or a brand-new name to create-and-apply.
async function applyOrCreateTag(key: string, target: { id?: number; name?: string }, ids: number[]): Promise<void> {
  const baseUrl = getOneHealthBaseUrl()
  const params = new URLSearchParams(target.id != null ? { id: String(target.id) } : { name: target.name! })
  const response = await authFetch(`${baseUrl}/api/v2/tag/${key}?${params}`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(ids),
  })
  if (!response.ok) throw new Error(`Apply/create tag failed: ${response.status}`)
}

// MERGE — fold one tag into another; optionally deactivate the source.
async function mergeTag(sourceTagId: number, targetTag: { id: number; name: string }, disableSource = true): Promise<void> {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/v2/tag/${sourceTagId}/migrate`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ targetTag, disable: disableSource }),
  })
  if (!response.ok) throw new Error(`Merge tag failed: ${response.status}`)
}
```

## Gotchas

- Tags aren't reachable via `POST /query` in practice — `LabelTag` is read via `POST /api/graphql`, a third read path alongside `/query` and the grid family.
- Apply and remove use **different body shapes** for the same target-id list — copy-pasting one into
  the other silently sends the wrong shape. This generalizes well beyond tags: every bulk
  id-mutation endpoint on the platform invents its own body shape — a bare array (this recipe's
  apply call), `{ instanceIds }` (this recipe's remove call), `{ idsToAdd, idsToRemove }` (a
  many-to-many membership change elsewhere), `{ idsToSet, idsToUnset }` (a boolean-flag toggle
  elsewhere). Read each specific endpoint's own contract; never assume one shape generalizes.
- The path segment right after `/tag/` (e.g. `journey`) names the **target type** being tagged — one
  of a small fixed set (journey, order, insurance, contact-point, organization,
  workflow-template-group, …) — not the tag itself; easy to misread as a tag identifier.
- Apply is per-tag (`?id={tagId}` singular) — there's no "apply these N tags in one call."
- A bulk-import job's own tag options (see [bulk-import.md](bulk-import.md)) can carry a third
  semantic beyond apply/remove — replace every tag on the imported rows with a given set in one
  shot. That's a property of the import call, not a separate tag endpoint of its own.
- Scope the `LabelTag` list by `createdByTenantId` — tags are tenant-owned, and an unscoped read can surface another tenant's tags in a shared environment.
- There's no "tags common to all of these" query — intersect per-record tag sets client-side.

## Related

- [query-the-data-graph.md](query-the-data-graph.md) — GraphQL is a sibling read path; see its Gotchas re: "a third read path exists."
- [grid-list-views.md](grid-list-views.md) — the `label-tag` grid view, for an admin tag-management screen.
- [bulk-import.md](bulk-import.md) — the import options' own tag add/remove/replace semantics.
- [bulk-assignment.md](bulk-assignment.md) — another bulk grid action from the same app.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md).
