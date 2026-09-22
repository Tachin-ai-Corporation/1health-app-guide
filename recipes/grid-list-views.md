# Grid list views

**Use when:** you're replicating a server-defined table/list view (a campaign's patient list, a
comment list, a user list) rather than doing a flexible entity+relationship read. Grid rows come
back pre-flattened, with a standard paginated envelope.
**Routes:** `POST /api/v3/health/grid/<view>` → [agents.md](https://agents.1health.io/public/prod/api/v3/health/grid/journey/agents.md)
(the `journey` view, as a concrete example — see the [manifest](https://agents.1health.io/public/prod/api/manifest.md) for the full list of views)
**Reference code:** [`lib/api/grid.ts`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/lib/api/grid.ts) (baseline fetch-all) · [`lib/api/journey-grid.ts`](https://github.com/Tachin-ai-Corporation/v0-trc-care-coordinator/blob/main/lib/api/journey-grid.ts#L1461) (production truncation-detection)
**Seen in:** most example apps (the standard list/table engine); truncation detection hardened in trc-care-coordinator after a real missing-records bug

## Pattern

1. Call the grid endpoint for your view, scoped first by an id — pass the owning
   campaign/list/tenant id as the **first** `filterBy` entry, or you'll page through every row in
   the system.
2. Page with `page`/`size` (not `offset`/`limit`) — the response is pre-flattened (plain field
   names, no `ROOT.`/edge prefixes) and carries a standard envelope: `data`, `totalElements`,
   `lastPage`, `numberOfElements`.
3. Loop until `lastPage === true`, but don't trust that flag alone — also stop on a short page
   (`data.length < size`) or a page that adds nothing new, since not every deployment sets
   `lastPage` reliably or honors the `page` param.
4. Track `totalElements` across pages and compare it, **after** the walk, to how many rows you
   actually read. If you read fewer, flag the result as truncated — never stop the walk early just
   because you think you've reached the total (a stale or per-page total would cut it short).
5. Bound both the page count and the record count with a hard ceiling, so a larger-than-expected
   view can't hang a client-driven read. Log and flag truncation when you hit the ceiling.
6. For a long export-style read, accept an `AbortSignal` and a progress callback.

## Minimal example

```ts
import { runGridQuery } from "@/lib/api"

interface FetchAllResult<T> {
  rows: T[]
  /** True if the walk stopped before reading everything the server reported. */
  truncated: boolean
}

export async function fetchAllRows<T>(
  view: string,
  filterBy: { key: string; value: string | number; operator: "equals" | "contains" | "in" }[],
  { pageSize = 100, maxPages = 200 } = {},
): Promise<FetchAllResult<T>> {
  const rows: T[] = []
  let rowsSeen = 0
  let totalElements: number | undefined
  let truncated = false

  for (let page = 0; page < maxPages; page++) {
    const res = await runGridQuery<T>(view, { filterBy, page, size: pageSize })
    if (!res.success || !res.data) { truncated = true; break }

    const { data, totalElements: total, lastPage } = res.data
    rowsSeen += data.length
    totalElements = total ?? totalElements
    rows.push(...data)

    if (lastPage === true || data.length < pageSize) break
    if (page === maxPages - 1) truncated = true
  }

  // The server's reported count is only used to CHECK the walk, never to end it early —
  // a stale or per-page total would otherwise truncate the result silently.
  if (totalElements !== undefined && rowsSeen < totalElements) truncated = true

  return { rows, truncated }
}
```

## Gotchas

- Rows are pre-flattened (plain field names) — this is a different shape from `/query`'s
  `ROOT.`-prefixed envelope; don't reuse a `/query` mapper here, and don't reuse a grid mapper there.
- A grid view is almost always pre-scoped by an id — omitting that first `filterBy` entry reads
  the whole view, not "your" slice of it.
- `lastPage` isn't sufficient alone: a deployment that ignores the `page` param will keep replaying
  page 0 forever — also stop when a page adds nothing new, not just when it's empty.
- Grid filter operators are a small fixed set (`equals`, `contains`, `greaterThan`, `lessThan`,
  `in`) — this is not RSQL; don't port `/query` filter strings here.
- Silently presenting a truncated list as complete is worse than surfacing the truncation — always
  propagate the flag to the UI/export rather than swallowing it.

## Related

- [query-the-data-graph.md](query-the-data-graph.md) — the other read engine; use it instead for
  relationships or a custom projection.
- [enrich-grid-with-custom-data.md](enrich-grid-with-custom-data.md) — joining a grid page with a
  bulk `customData` read.
- [batched-enrichment.md](batched-enrichment.md) — backfilling one extra field the grid response
  omits.
- [../api/README.md](../api/README.md)
