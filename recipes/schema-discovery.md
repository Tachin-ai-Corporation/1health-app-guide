# Discover types & attributes at runtime

**Use when:** you don't want to hardcode a type's attribute/relationship names — generic tooling
(a query builder, an admin UI, an export column mapper) — or you just need the exact `attrKey` /
`relKey` string a query requires.
**Routes:** `GET /api/v2/type/all` → [agents.md](https://agents.1health.io/public/prod/api/v2/type/all/agents.md) · `GET /api/v2/type/key/{typeName}` → [agents.md](https://agents.1health.io/public/prod/api/v2/type/key/agents.md)
**Reference code:** [`lib/api/schema.ts`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/lib/api/schema.ts) (canonical: cache + dedupe + prefetch) · [`lib/api/type-metadata.ts`](https://github.com/chill-tachin/v0-1h-query-helper/blob/main/lib/api/type-metadata.ts) (original production implementation)
**Seen in:** query-helper (an engineer-facing query builder built entirely on this), trc-care-coordinator, and the app template baseline

## Pattern

1. List all types via `/type/all` when you need a picker; otherwise call `/type/key/{typeName}`
   directly once you know the `boKey`.
2. Fetch one type's full definition: `attributes[]` (each with `attrKey`, `type`, and
   `attributeValues` for enums) and `relationships[]` (each with `relKey`, `direction`,
   `fromBoClassName`/`toBoClassName`).
3. Cache each `TypeDefinition` in memory and dedupe concurrent in-flight requests for the same
   type — the same type gets asked for repeatedly (once per field picker render, once per
   relationship expansion), and a naive implementation refetches every time.
4. Prefetch several types in parallel when you know them up front; lazy-load a relationship's
   target type only when the user actually expands it, rather than walking the whole graph eagerly.
5. Prepend the baseline attributes (`id`, `created`, `updated`) yourself — every instance has them,
   but they are **not** returned in `attributes[]`.
6. Drive a type-aware filter UI off `operatorsForType(attr.type)` instead of offering every RSQL
   operator for every attribute.

## Minimal example

```ts
import { fetchTypeDetails, prefetchTypeDetails, operatorsForType, BASELINE_ATTRIBUTES } from "@/lib/api"

// One type, cached + deduped even if called from several components at once.
const person = (await fetchTypeDetails("Person")).data!
const fieldPicker = [...BASELINE_ATTRIBUTES, ...person.attributes]
  .map((a) => ({ key: a.attrKey, label: a.name }))

// Several types in parallel, for a picker that spans more than one type.
const byType = await prefetchTypeDetails(["Person", "Organization", "Insurance"])

// Drive a filter dropdown off the attribute's real type.
const birthDate = person.attributes.find((a) => a.attrKey === "birthDate")!
operatorsForType(birthDate.type) // => ["==","!=","=gt=","=ge=","=lt=","=le=","range"]
```

## Gotchas

- **`attrKey` (not `name`) is what you put in a query's `attributes`/`filter`** — `name` is only
  the display label and can contain spaces/casing you don't want in a request.
- Baseline attributes (`id`, `created`, `updated`) exist on every instance but are **not** in
  `attributes[]` — a field picker built only from the response undercounts.
- Soft-deleted attributes/relationships (`isDeleted: true`) come back in the raw payload — filter
  them out before showing a picker (the reference implementation does this for you).
- `boKey`/type names may contain spaces in their display `name` — strip spaces before using a
  value as a query `key` or a relationship-path segment.
- This covers **schema attributes** only. A workflow step's dynamic fields are a different,
  per-environment GUID-keyed mechanism resolved by label, not by this endpoint.
- Discovery is optional, not mandatory — for a fixed app, pinning a handful of `attrKey`s as
  constants is fine and skips the round trip; reach for discovery for generic/dynamic tooling.

## Related

- [query-the-data-graph.md](query-the-data-graph.md) — where the discovered `attrKey`s and
  `filter` get used.
- [relationship-path-building.md](relationship-path-building.md) — turning a discovered
  relationship into a query path.
- [graphql-read-path.md](graphql-read-path.md) — for attributes that live on the relationship/edge
  record itself, which this endpoint doesn't expose.
- [../api/README.md](../api/README.md)
