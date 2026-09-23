# Paginate & sort /query

**Use when:** you need every row of a `/query` result, or a specific order, and can't rely on the
platform's default order alone.
**Routes:** `POST /api/v2/query` → [agents.md](https://agents.1health.io/public/prod/api/v2/query/agents.md) (same route as [query-the-data-graph.md](query-the-data-graph.md))
**Reference code:** [`lib/api/payer-record-query.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/api/payer-record-query.ts#L120)
**Seen in:** pcp-transitional-care-management (written specifically to fix a "newest records never
seen" bug on a long-lived feed)

## Pattern

1. Pass the `sort` query parameter explicitly on every call — `ASC` or `DESC`, ordering by the
   instance's internal id. The documented default when it's omitted or invalid is `DESC`
   (newest-first by id), but set it yourself every time rather than leaning on that default (see
   Gotchas).
2. Read the documented paging envelope alongside `data`: `pageNumber`, `pageSize`, `totalElements`,
   `totalPages`, `firstPage`, `lastPage`, `emptyPage`. Page with the body's `limit` + `offset` until
   `lastPage` is `true`. `offset` is the number of **rows** to skip, not a page index (so page *n* is
   `offset: n * limit`); the envelope's `pageNumber` is derived from it. Confirmed against the demo
   environment: with an explicit `sort`, consecutive offsets return contiguous, non-overlapping pages.
3. Treat a short page (`data.length < limit`) as an equally valid stop signal alongside `lastPage` —
   a safety net for a deployment where the envelope's flags don't behave exactly as documented, or
   where a concurrent write shifts `totalElements` mid-walk.
4. `sort` only orders by internal row id — for "newest/oldest by an actual attribute" (a timestamp
   field, a display name, anything that isn't id), fall back to paging everything and sorting
   client-side: project just what you need to sort by, page to exhaustion, then sort locally.
5. Select the slice you actually want (e.g. "newest 50") from the server-sorted page or the
   fully-paged, locally-sorted set — never from whichever page happened to load first.
6. Degrade gracefully: if the **first** page fails, there's nothing to show, so surface the error;
   if a **later** page fails, keep what's already read (a partial answer beats none) and log it.

## Primary vs fallback

- **Primary — server `sort` + envelope paging:** pass `sort=ASC` or `sort=DESC` explicitly and page
  with the documented envelope. Use this whenever "newest/oldest by id" is an acceptable order —
  it's real, documented, server-side ordering, and skips a full client-side walk.
- **Fallback — client-side sort:** switch the moment you need order by anything other than internal
  id. Page to exhaustion projecting only the sort attribute (plus `id`), then sort locally; keep
  paging until a short page as a safety net regardless of which path you're on.

## Minimal example

```ts
import { callApi } from "@/lib/api"

const PAGE_SIZE = 200
const MAX_PAGES = 25

interface Row { id: number; created?: string }

/** Primary: server-ordered by id. Always pass `sort` explicitly — never the bare default. */
async function fetchNewestByIdPage(filter: string, limit: number): Promise<Row[]> {
  const res = await callApi<{ data: Array<{ attributes: Record<string, unknown> }> }>(
    "query/page",
    "/api/v2/query?sort=DESC", // newest-first by id, explicit
    { method: "POST", body: JSON.stringify({ key: "Person", attributes: ["id", "created"], filter, limit, offset: 0 }) },
  )
  if (!res.success || !res.data) throw new Error("query failed")
  return res.data.data.map((r) => ({
    id: Number(r.attributes["ROOT.Person.id"]),
    created: r.attributes["ROOT.Person.created"] as string | undefined,
  }))
}

/** Fallback: order by a real attribute (not id) — page everything, sort locally. */
async function fetchAllIdsNewestByAttribute(filter: string, max: number): Promise<number[]> {
  const rows: Row[] = []

  for (let page = 0; page < MAX_PAGES; page++) {
    const res = await callApi<{ data: Array<{ attributes: Record<string, unknown> }>; lastPage?: boolean }>(
      "query/page",
      "/api/v2/query?sort=ASC", // explicit even though this path sorts locally anyway
      {
        method: "POST",
        body: JSON.stringify({
          key: "Person", // placeholder type
          attributes: ["id", "created"],
          filter,
          limit: PAGE_SIZE,
          offset: page * PAGE_SIZE,
        }),
      },
    )
    if (!res.success || !res.data) {
      if (page === 0) throw new Error("query failed on the first page")
      break // keep what's already in hand rather than losing the whole read
    }

    const batch = res.data.data.map((r) => ({
      id: Number(r.attributes["ROOT.Person.id"]),
      created: r.attributes["ROOT.Person.created"] as string | undefined,
    }))
    rows.push(...batch)
    if (res.data.lastPage || batch.length < PAGE_SIZE) break // either stop signal ends the walk
  }

  rows.sort((a, b) => (b.created ?? "").localeCompare(a.created ?? "")) // by the real attribute, client-side
  return rows.slice(0, max).map((r) => r.id)
}
```

## Gotchas

- **Always pass `sort` explicitly.** The documented default (id `DESC`) held when checked against the
  demo environment, and `sort` is case-insensitive with invalid values falling back to `DESC` — but an
  earlier app observed oldest-first with no `sort` sent, so don't lean on the default.
- **Scope queries on very large types.** An unfiltered `/query` over a type with a very large
  population (e.g. `Person` in a big tenant) can take longer than a typical request timeout — add a
  `filter` (by owner, campaign, date range, …) before paging it.
- `sort` orders by internal row id only — it's not a stand-in for "newest by an actual timestamp
  field"; use the client-side fallback for that.
- Stop on `lastPage` **or** a short page, not by comparing counts to `totalElements` — a write
  during a long walk can shift the total out from under you.
- A free-text "quick filter" on a `/query`-backed list should debounce (roughly 500ms–1s) and be
  sent as part of the next server request whenever rows are server-paged — filtering only what's
  already loaded silently hides matches on pages you haven't fetched.
- A "load more" that only grows how much of an already-fetched array is *rendered* (no new network
  call) is fine **only** when the whole result set is already loaded for another reason (e.g. a
  client-side sort/group pass) — it doesn't reduce what you fetched, only what you render; don't use
  it as a substitute for real paging on a large or growing set.
- Split "page everything" from "pick what you want": page cheaply on `id` + the sort attribute only,
  then select client-side, so an expensive per-record follow-up fetch stays bounded to the rows you
  actually selected — and if you do fan out those follow-up calls, cap their concurrency.

## Related

- [query-the-data-graph.md](query-the-data-graph.md) — the base `/query` mechanics this recipe
  paginates and sorts.
- [grid-list-views.md](grid-list-views.md) — the grid engine's own `orderBy`; prefer it when the
  view you need already exists there.
- [bulk-read-and-export.md](bulk-read-and-export.md) — turning a full paged walk into a
  client-built export file.
- [batched-enrichment.md](batched-enrichment.md) — batching the follow-up reads for the ids you
  select.
- [../api/README.md](../api/README.md)
