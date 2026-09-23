# Read & write custom data

**Use when:** you need to store or read app-specific fields that the platform schema doesn't model
— audit fields, cross-workflow bookkeeping, per-app config, UI state. Custom data is the
platform's built-in extension point: a schemaless JSON blob on any extensible instance.
**Routes:** read via `POST /api/v2/query` (project `customData`) or `POST /api/v2/data/custom-data` → [agents.md](https://agents.1health.io/public/prod/api/v2/data/custom-data/agents.md) · write via
`POST /api/v2/data/custom-data/bulk` → [agents.md](https://agents.1health.io/public/prod/api/v2/data/custom-data/bulk/agents.md)
**Reference code:** [`lib/api/custom-data.ts`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/lib/api/custom-data.ts)
**Seen in:** most example apps (app state that isn't first-class schema)

## Pattern

1. **Namespace your data** under `appData.<appId>` so multiple apps sharing an instance don't
   clobber each other.
2. **Read** it as an attribute of its owning instance, or read it directly for a list of instance ids.
3. **Write** with the bulk endpoint, choosing the operation deliberately:
   - `APPEND` — shallow, **top-level-only** merge. Good for flat top-level fields.
   - `REPLACE` — overwrites the whole blob.
   - `CLEAR` — **wipes the instance's entire blob**, other apps' namespaces included. The API accepts
     it only with an empty (or null) `customData`; any keys you send are rejected with a 400.
4. **For nested/namespaced updates, read → deep-merge client-side → write** — because APPEND does
   not deep-merge. Use the merge helper; don't hand-roll it.
5. **Delete a key** by omission: read → drop → `REPLACE`. There is no per-key delete — `CLEAR` only
   ever removes everything.

## Primary vs fallback

- **Primary — read `customData` inside the `/query` you're already making** for that instance: one
  round trip gets the record and its blob.
- **Fallback — `POST /api/v2/data/custom-data` with an array of instance ids** when you only need the
  blobs (for example, to enrich rows you already have): it returns `id`, `typeKey`, `name`, and
  `customData` for each.

## Minimal example

```ts
import { readCustomData, appendCustomData, mergeCustomData, appData, deleteCustomDataKeys } from "@/lib/api"

// READ
const data = await readCustomData("Organization", orgId)      // => Record<string, unknown>

// WRITE a flat top-level field (other top-level keys survive)
await appendCustomData(orgId, { lastSyncedAt: "2026-07-23T00:00:00Z" })

// WRITE one nested/namespaced field SAFELY (siblings + other apps' data survive)
await mergeCustomData("Organization", orgId, appData(appId, { phase: "review" }))
// => customData.appData["<appId>"].phase = "review"

// DELETE keys (read → drop → REPLACE)
await deleteCustomDataKeys("Organization", orgId, ["staleKey"])
```

## Gotchas

- **⚠️ APPEND is a shallow, top-level-only merge — it does NOT deep-merge.** A partial write under
  a nested key like `appData.<appId>` replaces that **entire** subtree, silently wiping its sibling
  keys *and* other apps' namespaces. This is the #1 custom-data footgun.
  **Rule of thumb: flat top-level field → `appendCustomData`; anything nested → `mergeCustomData`.**
- **`customData` may come back as a JSON string**, not an object — always parse (the read helper does).
- **No per-key delete** — remove keys by read → drop → `REPLACE`. APPENDing a payload *without* a key
  does not remove it.
- **⚠️ `CLEAR` is all-or-nothing.** `{ customData: {}, operation: "CLEAR" }` erases every key on the
  instance, including other apps' `appData.<appId>` namespaces. Sending specific keys (even as `null`)
  is rejected. Use it only when your app owns the whole blob.
- **Filtering on deeply-nested `customData` in `/query` is unreliable** — validate client-side when
  correctness matters; keep anything you must filter/sort on as a real schema attribute instead.
- **`appId`** is your app's own namespace key (commonly `NEXT_PUBLIC_APP_ID`) — **not** a 1health
  object-type or attribute id.

## Related

- [query-the-data-graph.md](query-the-data-graph.md) — how you read the blob back.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md) (§ customData, § deletion).
