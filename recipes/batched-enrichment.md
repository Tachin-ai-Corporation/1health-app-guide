# Batch-enrich with id=in=()

**Use when:** a grid/bulk response you already fetched is missing one field you need (e.g. a real
step-completion timestamp), and you don't want an N+1 call-per-row loop to backfill it.
**Routes:** `POST /api/v2/query` (RSQL `id=in=(...)`) → [agents.md](https://agents.1health.io/public/prod/api/v2/query/agents.md)
(same route as query-the-data-graph.md) — or a dedicated bulk-by-id endpoint where the type has one
(see enrich-grid-with-custom-data.md for the `customData` case)
**Reference code:** [`lib/api/export-completed-dates.ts`](https://github.com/Tachin-ai-Corporation/v0-trc-care-coordinator/blob/main/lib/api/export-completed-dates.ts#L33)
**Seen in:** trc-care-coordinator (`/query` with `id=in=()`); med-adherence-bcbsm (the same
batched-by-id shape, via `customData`'s own bulk-read endpoint — see enrich-grid-with-custom-data.md)

## Pattern

1. Start from a list of ids you already have (a grid page, a prior query) — this enriches rows you
   already fetched, it doesn't page a new source.
2. Split the ids into fixed-size batches (a few dozen up to ~50 is a safe default) — one request
   per batch, not one per id.
3. For a `/query`-shaped batch: filter `id=in=(id1,id2,...)`, project only the id plus the field(s)
   you need, and — if the field lives on a relationship — eager-load just that one relationship at
   `limit: 1`.
4. Map each result back to its source row **by id** — never assume response order matches request
   order.
5. Fall back deliberately for any id that didn't come back (miss, error, or an empty relationship)
   — a documented default (e.g. an existing timestamp) beats leaving the field undefined.
6. Report progress per batch, and accept an `AbortSignal` if this runs during a long client-driven
   export.

## Minimal example

```ts
import { callApi } from "@/lib/api"

const BATCH_SIZE = 50

/** Backfill one relationship-sourced field a bulk/grid response omits, keyed by id. */
async function resolveExtraField(
  ids: number[],
  fallback: (id: number) => string,
): Promise<Map<number, string>> {
  const result = new Map<number, string>()

  for (let i = 0; i < ids.length; i += BATCH_SIZE) {
    const batch = ids.slice(i, i + BATCH_SIZE)
    const res = await callApi<{ data: any[] }>("enrich/batch", "/api/v2/query", {
      method: "POST",
      body: JSON.stringify({
        key: "Organization",       // placeholder type — whatever your ids reference
        attributes: ["id"],
        filter: `id=in=(${batch.join(",")})`,
        relationships: [{ key: "Organization.OrgHasField.FieldRecord", attributes: ["id", "value"], limit: 1 }],
        limit: batch.length,
      }),
    })

    if (res.success && res.data) {
      for (const row of res.data.data) {
        const id = Number(row.attributes["ROOT.Organization.id"])
        const rel = row.relationships?.["Organization.OrgHasField.FieldRecord"]?.[0]
        const value = rel?.instance?.attributes?.["OrgHasField.FieldRecord.value"]
        result.set(id, value ?? fallback(id))
      }
    }
    // On a batch failure, every id in it falls through to `fallback` below.
  }

  for (const id of ids) if (!result.has(id)) result.set(id, fallback(id))
  return result
}
```

## Gotchas

- Batch size is a tradeoff, not a constant to copy blindly — big enough to keep round trips few,
  small enough that one request/response body stays manageable; ~50 is a proven default.
- Never assume result order matches request order — always key the map by the id you read back,
  not by array position.
- A missed id (filtered server-side, a null relationship, a batch that errored) needs an explicit
  fallback — an unresolved field silently rendering as blank is a worse failure than a slightly
  stale fallback value.
- This is a stopgap for "the bulk source is missing one field," not a substitute for fixing the
  bulk source — batch-enriching more than one or two fields is a sign the grid/customData should
  just carry the field.
- The bulk-by-id shape isn't always `/query` with `id=in=()` — some data (like `customData`) has
  its own dedicated bulk-read endpoint; use whichever the type actually offers.

## Related

- [query-the-data-graph.md](query-the-data-graph.md) — the `/query` mechanics this batches.
- [grid-list-views.md](grid-list-views.md) — the usual source of the id list you're enriching.
- [enrich-grid-with-custom-data.md](enrich-grid-with-custom-data.md) — the `customData`-specific
  version of this same idea.
- [../api/README.md](../api/README.md)
