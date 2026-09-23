# Cache reference data in custom data

**Use when:** you've resolved a value from an external reference lookup (or any other external
call) and you'll need it again for the same record — cache it onto the 1health instance it
describes instead of re-hitting the external source (or your own proxy) every time.
**Routes:** same as [read-write-custom-data.md](read-write-custom-data.md) — read via
`POST /api/v2/query`, write via `POST /api/v2/data/custom-data/bulk`.
**Reference code:** [`lib/npi/registry.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/npi/registry.ts) (the cached value's source) — the caching write itself is the same primitive as [read-write-custom-data.md](read-write-custom-data.md)
**Seen in:** pcp-tcm

> **Scope check:** this recipe is for caching an *external* lookup result onto the **specific
> record** it describes — durable, cross-device. For *global* metadata that isn't "about" any one
> record — a type's schema, a grid config, branding — use a per-session client-memory cache with a
> TTL instead (see [schema-discovery.md](schema-discovery.md)'s caching step); don't write that kind
> of value onto a platform record just because it's also "reference data."

## Pattern

1. **After a successful external lookup, write the normalized result into the owning instance's
   `customData`** under your app's namespace — the same namespaced-merge write as any other
   app-specific field (see [read-write-custom-data.md](read-write-custom-data.md)).
2. **Read your own cache first.** Before calling the external source (or your proxy) again, check
   whether the instance's `customData` already has a fresh-enough value; only fall through to the
   external call on a cache miss or stale entry.
3. **Timestamp what you cache.** Store when the value was fetched alongside the value itself, so
   "fresh enough" is a real decision (a TTL check) rather than "cached forever, possibly wrong
   forever."
4. **Cache the resolved, normalized shape — not the raw vendor response** — so a later reader
   doesn't need to know anything about the external API to use it.

## Minimal example

```ts
import { readCustomData, mergeCustomData, appData } from "@/lib/api"

const CACHE_KEY = "referenceProfile"
const TTL_MS = 30 * 24 * 60 * 60 * 1000 // reference data changes rarely — 30 days is plenty

interface CachedProfile { value: Record<string, unknown>; fetchedAt: string }

export async function getOrFetchReferenceProfile(
  ownerType: string,
  ownerId: number,
  appId: string,
  fetchFresh: () => Promise<Record<string, unknown>>,
) {
  const current = await readCustomData(ownerType, ownerId)
  const cached = (current.appData as any)?.[appId]?.[CACHE_KEY] as CachedProfile | undefined

  if (cached && Date.now() - new Date(cached.fetchedAt).getTime() < TTL_MS) {
    return cached.value // cache hit — no external call
  }

  const value = await fetchFresh() // e.g. your public-reference-api-proxy.md route
  await mergeCustomData(ownerType, ownerId, appData(appId, {
    [CACHE_KEY]: { value, fetchedAt: new Date().toISOString() },
  }))
  return value
}
```

## Gotchas

- **Use the deep-merge write (`mergeCustomData`/`appData`), not a raw APPEND** — a shallow APPEND
  under your namespace would wipe sibling app fields, same as any other nested customData write.
- **A cache with no TTL is a value you can never safely trust again** — always store a fetch
  timestamp and decide staleness explicitly.
- **Cache the *normalized* result, not the vendor's raw payload** — a later reader shouldn't need
  to know the external API's shape at all.
- **This is a cache, not a system of record for the external source** — if the upstream data
  changes (e.g., a provider's registry listing), your cached copy won't know until it's next
  refreshed.
- **Not every "reference data" cache belongs on a platform record.** Global metadata (a type's
  schema, a grid config) is cheap enough, and shared by enough unrelated records, that a per-session
  client-memory cache with a TTL is the better tool — reserve this recipe's platform-record write
  for a value that's genuinely an attribute of the one record it's cached on.

## Related

- [public-reference-api-proxy.md](public-reference-api-proxy.md) — the usual source of the value
  being cached.
- [read-write-custom-data.md](read-write-custom-data.md) — the underlying write mechanism.
- [schema-discovery.md](schema-discovery.md) — the client-memory + TTL pattern for global/type-level
  reference data (a different job than this recipe).
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
