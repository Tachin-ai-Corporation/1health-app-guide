# Grid list views

**Use when:** you're replicating a server-defined table/list view (a campaign's patient list, a
comment list, a user list) rather than doing a flexible entity+relationship read. Grid rows come
back pre-flattened, with a standard paginated envelope.
**Routes:** `POST /api/v3/health/grid/<view>` → [agents.md](https://agents.1health.io/public/prod/api/v3/health/grid/journey/agents.md)
(the `journey` view, as a concrete example — see the [manifest](https://agents.1health.io/public/prod/api/manifest.md) for the full list of views)
**Reference code:** [`lib/api/grid.ts`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/lib/api/grid.ts) (baseline fetch-all) · [`lib/api/journey-grid.ts`](https://github.com/Tachin-ai-Corporation/v0-trc-care-coordinator/blob/main/lib/api/journey-grid.ts#L1461) (production truncation-detection)
**Seen in:** most example apps (the standard list/table engine); truncation detection hardened in trc-care-coordinator after a real missing-records bug · 1health platform usage (view catalog, dual REST dialects, master-detail grids)

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
7. Confirm the view exists and get its exact name before wiring a screen to it — the view catalogue
   spans dozens of names (`patient`, `order`, `sample`, `kit`, `comment`, `label-tag`,
   `workflow-campaign`, `user`, …); grep the [manifest](https://agents.1health.io/public/prod/api/manifest.md)
   for `/v3/health/grid/` rather than guessing one.
8. This structured `filterBy`/`orderBy` body is this engine's own dialect. Other REST list endpoints
   in the platform can instead take an RSQL query string (the same style `/query` uses) — don't port
   one style to the other, and don't assume every "list" screen in the app is backed by this same engine.
9. GraphQL is an equally valid data source for the same list-screen job wherever the platform models
   the thing as its own GraphQL business type (see [graphql-read-path.md](graphql-read-path.md)) —
   not a rare escape hatch. See [choose-a-read-path.md](choose-a-read-path.md) for the full decision
   across grid / `/query` / GraphQL.
10. For a parent/detail table (e.g. an order with its samples, kits, comments), prefer a parent view
    that returns a small integer **count** per child collection instead of embedding the child rows.
    Expand a row to trigger its own scoped grid call for just that child collection — the parent id
    as the first, non-removable filter — so unexpanded rows stay cheap.
11. When the same view must serve more than one caller role, and a role has no legitimate reason to
    see certain columns (e.g. patient name/DOB for a fulfillment-only role), look for an alternate,
    role-scoped view identifier that omits those columns server-side, rather than fetching the full
    row and hiding columns client-side.

## Minimal example

```ts
import { runGridQuery } from "@/lib/api"

interface FetchAllResult<T> {
  rows: T[]
  /** True if the walk stopped before reading everything the server reported. */
  truncated: boolean
}

type GridOperator =
  | "equals" | "notEqual" | "contains" | "blank" | "notBlank"
  | "greaterThan" | "lessThan" | "in" | "inRange"

interface GridFilter {
  key: string
  operator: GridOperator
  /** Omit for blank/notBlank; an array for "in"; { startDate, endDate } for a date "inRange". */
  value?: string | number | (string | number)[] | { startDate: string; endDate: string }
}

export async function fetchAllRows<T>(
  view: string,
  filterBy: GridFilter[],
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
- Grid filter operators (confirmed against the demo environment): `equals`, `notEqual`, `contains`,
  `blank`, `notBlank`, `greaterThan`, `lessThan`, `in`, and `inRange` for **dates only**. This is not
  RSQL — don't port `/query` filter strings here.
  - `in` takes an **array** value; a comma-separated string is rejected with a 400.
  - Date `inRange` takes `value: { startDate, endDate }` (inclusive); plain dates and ISO timestamps
    both work. On a numeric column, combine `greaterThan` + `lessThan` instead.
  - `notContains` and `startsWith` are rejected. Which operators a column accepts depends on its
    type — a 400 "invalid operator … for attribute of type …" means that pairing isn't supported.
  - Multiple filters are ANDed; for OR within one column, use `in`.
- Silently presenting a truncated list as complete is worse than surfacing the truncation — always
  propagate the flag to the UI/export rather than swallowing it.
- A string value of literal `"n/a"` in a row can mean **unset**, not the text "n/a" — check for that
  sentinel in addition to null/empty when mapping a row for display, in one shared row-mapping
  helper rather than ad hoc at each call site.
- A child-collection **count** and a boolean "has children" flag look identical in a truthy check —
  remember the count is already in the parent row if you just need to *display* it (a badge), no
  extra call needed.

## Related

- [query-the-data-graph.md](query-the-data-graph.md) — the other read engine; use it instead for
  relationships or a custom projection.
- [choose-a-read-path.md](choose-a-read-path.md) — the full decision across grid / `/query` / GraphQL.
- [enrich-grid-with-custom-data.md](enrich-grid-with-custom-data.md) — joining a grid page with a
  bulk `customData` read.
- [batched-enrichment.md](batched-enrichment.md) — backfilling one extra field the grid response
  omits.
- [../api/README.md](../api/README.md)
