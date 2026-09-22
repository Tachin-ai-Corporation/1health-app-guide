# Paginate & sort /query

**Use when:** you need EVERY row of a `/query` result (not just page 0) in a specific order —
`/api/v2/query` has no documented `orderBy`/`sortBy` key, and its default order skews oldest-first.
**Routes:** `POST /api/v2/query` → [agents.md](https://agents.1health.io/public/prod/api/v2/query/agents.md) (same route as query-the-data-graph.md)
**Reference code:** [`lib/api/payer-record-query.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/api/payer-record-query.ts#L120)
**Seen in:** pcp-transitional-care-management (written specifically to fix a "newest records never
seen" bug on a long-lived feed)

## Pattern

1. Recognize the trap: a single `/query` call with `limit: N` and no `offset` loop reads whichever
   N rows the platform hands back first — and the platform's default order is **oldest-first**. On
   a feed that's been accumulating for a long time, that call quietly answers with the *stalest*
   rows, not "the" rows or the newest ones.
2. Page to exhaustion: loop `offset` in fixed-size batches, projecting only what you need to
   select with (commonly just `id` plus a sortable timestamp attribute) — keep this pass cheap
   since it may have to walk the whole history.
3. Treat a short page as the end, regardless of what the envelope's paging metadata claims —
   `/query` is not guaranteed to expose a reliable `totalElements`/`lastPage` for every deployment.
4. Sort **client-side**, after paging — `orderBy`/`sortBy` is not a documented key on this
   endpoint, and sending an unrecognized key risks a 400 that fails the whole read, which is worse
   than the ordering problem you're fixing. Requesting the sort attribute as an ordinary projected
   field and sorting locally needs nothing the platform hasn't already demonstrated.
5. Select the slice you actually want (e.g. "newest 50") from the fully-paged, locally-sorted set —
   never from whichever page happened to load first.
6. Degrade gracefully: if the **first** page fails, there's nothing to show, so surface the error;
   if a **later** page fails, keep what's already read (a partial answer beats none) and log it.

## Minimal example

```ts
import { callApi } from "@/lib/api"

const PAGE_SIZE = 200
const MAX_PAGES = 25

interface Row { id: number; created?: string }

/** Every matching row's id, newest-first — corrected client-side. */
async function fetchAllIdsNewestFirst(filter: string, max: number): Promise<number[]> {
  const rows: Row[] = []

  for (let page = 0; page < MAX_PAGES; page++) {
    const res = await callApi<{ data: Array<{ attributes: Record<string, unknown> }> }>(
      "query/page",
      "/api/v2/query",
      {
        method: "POST",
        body: JSON.stringify({
          key: "Person", // placeholder type
          attributes: ["id", "created"],   // NOT orderBy — sort happens locally, below
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
    if (batch.length < PAGE_SIZE) break // short page = end, whatever the envelope claims
  }

  rows.sort((a, b) => (b.created ?? "").localeCompare(a.created ?? "")) // newest first, client-side
  return rows.slice(0, max).map((r) => r.id)
}
```

## Gotchas

- `/api/v2/query` has **no documented server-side sort** — don't send `orderBy`/`sortBy`; an
  unrecognized key risks a 400 that takes down the whole read.
- The platform's default order skews **oldest-first** — a naive single-page call on a long-lived
  feed silently returns the stalest rows.
- Don't stop paging once you think you've read `totalElements` rows — a stale or per-page total
  would truncate the walk early. A short page is the trustworthy stop signal.
- Split "page everything" from "pick what you want": page cheaply on `id` + timestamp only, then
  select client-side, so an expensive per-record follow-up fetch stays bounded to the rows you
  actually selected — and if you do fan out those follow-up calls, cap their concurrency.

## Related

- [query-the-data-graph.md](query-the-data-graph.md) — the base `/query` mechanics this recipe
  paginates.
- [grid-list-views.md](grid-list-views.md) — the grid engine *does* support server-side `orderBy`;
  prefer it when the view you need already exists there.
- [batched-enrichment.md](batched-enrichment.md) — batching the follow-up reads for the ids you
  select.
- [../api/README.md](../api/README.md)
