# Bulk-read and export data

**Use when:** you need to build a CSV/export file (or any other full-set output) from more rows
than fit on one page, and the export must include everything matching, not just what's currently
loaded on screen.
**Routes:** `POST /api/v2/query` → [agents.md](https://agents.1health.io/public/prod/api/v2/query/agents.md) (same route as [query-the-data-graph.md](query-the-data-graph.md)) · fallback: `POST /api/v3/health/grid/<view>` → [agents.md](https://agents.1health.io/public/prod/api/v3/health/grid/journey/agents.md) (per view)
**Reference code:** [`lib/api/payer-record-query.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/api/payer-record-query.ts#L120) (the offset-loop mechanic this builds on) · [`lib/api/grid.ts`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/lib/api/grid.ts) (the grid-paging fallback)
**Seen in:** pcp-transitional-care-management (the offset loop); the grid-paging fallback is the
same mechanism as [grid-list-views.md](grid-list-views.md)

## Pattern

1. Don't reach for a server-side export job — page `/query` yourself in an offset loop instead.
   This is a deliberate substitute for async export jobs, not a stopgap (see Gotchas).
2. Always pass `sort` explicitly on every page (see
   [query-pagination-and-sorting.md](query-pagination-and-sorting.md)) so the same order is used
   call to call — an implicit/default order can let a concurrent write reshuffle rows between
   pages, causing a row to be skipped or duplicated.
3. Loop `offset` in a fixed page size, projecting only the fields the export actually needs. Stop
   on `lastPage` from the response envelope, or on a short page — whichever comes first.
4. Do the filtering client-side: re-validate any filter beyond a simple RSQL match (and especially
   anything touching `customData`) against the actual field values before including a row, the same
   caution as [query-the-data-graph.md](query-the-data-graph.md).
5. Build the CSV/file entirely in the client from the rows you've accumulated — never ask the
   platform to generate the file for you here.
6. Dedupe the accumulated rows by `id` before writing the file. A write to the underlying data
   during a long export can shift offsets enough that the same row is read twice, on two different
   pages.
7. Show progress as rows read so far (treat a first-page `totalElements` as an estimate only, not a
   promise), and cap both the page count and the row count so a larger-than-expected result set
   can't hang the export.

## Primary vs fallback

- **Primary — the `/query` offset loop:** works for any type, gives full control over projection
  and client-side filtering, and is what this recipe is built around.
- **Fallback — page the grid instead:** when the screen is already backed by a grid view with the
  exact columns you need, page that grid the same way (`page`/`size`, stop on a short page or
  `lastPage`) rather than re-deriving the projection from `/query` — but still never an export job.

## Minimal example

```ts
import { callApi } from "@/lib/api"

const PAGE_SIZE = 200
const MAX_ROWS = 20_000 // hard cap so a runaway export can't hang the client

interface ExportRow { id: number; [key: string]: unknown }

/** Page /query to exhaustion, dedupe by id, and hand back rows ready to write to a file. */
async function exportAllRows(
  typeKey: string,
  attributes: string[],
  filter: string | undefined,
  onProgress?: (rowsSoFar: number) => void,
): Promise<ExportRow[]> {
  const seen = new Map<number, ExportRow>()

  for (let offset = 0; seen.size < MAX_ROWS; offset += PAGE_SIZE) {
    const res = await callApi<{ data: Array<{ attributes: Record<string, unknown> }>; lastPage?: boolean }>(
      "query/export-page",
      "/api/v2/query?sort=ASC", // explicit on every page — never the bare default
      { method: "POST", body: JSON.stringify({ key: typeKey, attributes, filter, limit: PAGE_SIZE, offset }) },
    )
    if (!res.success || !res.data) break

    for (const row of res.data.data) {
      const id = Number(row.attributes[`ROOT.${typeKey}.id`])
      seen.set(id, { id, ...row.attributes }) // de-dupe by id — offsets can shift mid-export
    }
    onProgress?.(seen.size)
    if (res.data.lastPage || res.data.data.length < PAGE_SIZE) break // either stop signal ends it
  }

  return [...seen.values()]
}
```

## Gotchas

- Don't use grid export jobs (`/v3/health/grid/export/run` and its status poll) — they're
  unreliable; this offset loop is the supported alternative, for any size export.
- **Scope before you page a very large type.** An unfiltered `/query` over a type with a huge
  population (e.g. `Person` in a big tenant) can outlast a normal request timeout — add a `filter`
  that narrows it (owner, campaign, date range) and filter the rest client-side.
- Always pass `sort` explicitly on every page — without it, a concurrent write can reorder rows
  between calls and cause a page to skip or repeat entries.
- Dedupe by `id` before writing the file — a write during a long export can shift offsets enough
  that the same row lands on two different pages.
- Treat any customData or otherwise-complex filter as advisory only — re-validate it client-side
  before including a row, rather than trusting the server-side match alone.
- Cap both the page count and the accumulated row count — an export with no ceiling can hang the
  tab on a larger-than-expected result set.

## Related

- [query-pagination-and-sorting.md](query-pagination-and-sorting.md)
- [query-the-data-graph.md](query-the-data-graph.md)
- [grid-list-views.md](grid-list-views.md)
- [batched-enrichment.md](batched-enrichment.md)
- [../api/README.md](../api/README.md)
