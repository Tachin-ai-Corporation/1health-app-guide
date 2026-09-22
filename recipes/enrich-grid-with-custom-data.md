# Join a grid page with bulk customData

**Use when:** a grid list view carries your schema-backed columns but not the app-specific
`customData` you also need per row (computed measures, provider notes) — join them client-side in
a second round trip instead of reading `customData` per row.
**Routes:** grid page via `POST /api/v3/health/grid/<view>` (see grid-list-views.md) · customData
read-many via `POST /api/v2/data/custom-data` → [agents.md](https://agents.1health.io/public/prod/api/v2/data/custom-data/agents.md)
**Reference code:** [`lib/api/custom-data.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-med-adherence-bcbsm/blob/main/lib/api/custom-data.ts#L862) (`fetchCustomDataBulk`) · [`provider-dashboard.tsx`](https://github.com/Tachin-ai-Corporation/v0-1health-med-adherence-bcbsm/blob/main/components/provider-dashboard/provider-dashboard.tsx#L404) (the join) · [`lib/api/campaign.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-med-adherence-bcbsm/blob/main/lib/api/campaign.ts#L45) (the grid call)
**Seen in:** med-adherence-bcbsm (provider dashboard: journey grid + per-patient measure data)

## Pattern

1. Fetch the grid page as normal (see grid-list-views.md) — this gives you the schema-backed
   columns plus each row's id.
2. Collect the ids from that page and send them in **one** call to the customData read-many
   endpoint: `POST /api/v2/data/custom-data` with a plain JSON array of ids as the body. This is a
   distinct endpoint from the customData **write** bulk endpoint (`/bulk` suffix) — don't confuse
   the two.
3. The response is a flat list keyed by `id`/`typeKey` (not `/query`'s prefixed envelope) — filter
   to the type you expect and build an `id -> customData` map.
4. Join client-side: map over the grid rows and look up each one's customData by id; treat a
   missing map entry as "no custom data yet," not an error.
5. Re-run both calls (grid page, then customData-by-id) on every page turn — this is a per-page
   join, not a one-time preload, unless your grid is small enough to load in full.
6. Keep the grid the source of truth for anything you filter/sort/paginate on — customData joined
   this way is display/derived-value only, since it isn't part of the grid's own filter/sort surface.

## Minimal example

```ts
import { runGridQuery, callApi, parseCustomData } from "@/lib/api"

async function fetchCustomDataByIds(ids: number[], typeKey: string): Promise<Map<number, Record<string, unknown>>> {
  const map = new Map<number, Record<string, unknown>>()
  if (ids.length === 0) return map

  // NOTE: no "/bulk" suffix — that's the WRITE endpoint. This one reads many by id.
  const res = await callApi<Array<{ id: number; typeKey: string; customData: unknown }>>(
    "customData/fetchManyByIds",
    "/api/v2/data/custom-data",
    { method: "POST", body: JSON.stringify(ids) },
  )
  if (!res.success || !res.data) return map

  for (const item of res.data) {
    if (item.typeKey === typeKey) map.set(item.id, parseCustomData(item.customData))
  }
  return map
}

// Page + join:
const page = await runGridQuery<{ id: number; name: string }>("journey", {
  filterBy: [{ key: "workflowCampaignId", value: campaignId, operator: "equals" }],
  page: 0,
  size: 50,
})
const rows = page.data?.data ?? []
const customDataById = await fetchCustomDataByIds(rows.map((r) => r.id), "WorkflowTemplate")

const enriched = rows.map((row) => ({
  ...row,
  measure: customDataById.get(row.id)?.["someMeasureField"] ?? null,
}))
```

## Gotchas

- **`POST /api/v2/data/custom-data` (read-many) has no `/bulk` suffix** — the visually similar
  `POST /api/v2/data/custom-data/bulk` is the WRITE endpoint (see read-write-custom-data.md).
  Mixing them up sends the wrong shape to the wrong verb.
- The bulk-read response is a flat array with plain `id`/`typeKey`/`customData` fields — nothing
  like `/query`'s `ROOT.`-prefixed envelope; don't reuse a `/query` row mapper on it.
- `customData` in this response can still arrive as a JSON **string** — parse defensively
  (`parseCustomData`), exactly as you would from `/query`.
- Filter the bulk-read response to the `typeKey` you expect — a shared id-space endpoint like this
  one has no obligation to only return your type.
- This is a display-time join, not a filter/sort mechanism — you cannot filter or sort the grid by
  a customData field this way; if you need that, mirror the field onto a real schema attribute the
  grid can see.
- The join must be re-run every time the grid page/filter changes — caching one global
  `id -> customData` map across unrelated pages risks serving stale values for rows you haven't
  re-fetched.

## Related

- [grid-list-views.md](grid-list-views.md) — the grid half of this join.
- [read-write-custom-data.md](read-write-custom-data.md) — the customData model, and the WRITE
  bulk endpoint this recipe's read endpoint is easy to confuse with.
- [batched-enrichment.md](batched-enrichment.md) — the general batched-by-id shape this is one
  instance of.
- [../api/README.md](../api/README.md)
