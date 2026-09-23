# Discover types & attributes at runtime

**Use when:** you don't want to hardcode a type's attribute/relationship names — generic tooling
(a query builder, an admin UI, an export column mapper) — or you just need the exact `attrKey` /
`relKey` string a query requires.
**Routes:** `GET /api/v2/type/all` → [agents.md](https://agents.1health.io/public/prod/api/v2/type/all/agents.md) · `GET /api/v2/type/key/{typeName}` → [agents.md](https://agents.1health.io/public/prod/api/v2/type/key/agents.md) · `GET /api/v2/type/{id}` → [agents.md](https://agents.1health.io/public/prod/api/v2/type/agents.md)
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
7. Derive list/grid columns from this same schema instead of hand-declaring them: map each
   attribute to a column definition — `attrKey`, display name, a filter widget chosen by the
   attribute's declared type, and (for an enumerated attribute) its own value-list option set as the
   filter's choices, minus any reserved "unset" placeholder entry. Fetch once per grid mount and
   memoize; a hand-authored static column list is still the better fit when a grid mixes fields from
   more than one type.

## Primary vs fallback

- **Primary — look up by string key** (`GET /api/v2/type/key/{typeName}`): the common case — you
  almost always know the type's name up front.
- **Fallback — look up by numeric id** (`GET /api/v2/type/{id}`): reach for this only when a prior
  response handed you a relationship's numeric class id (its `to`/`from` class id) rather than a
  name — resolving the key first would be a wasted extra round trip.

## Minimal example

```ts
import { fetchTypeDetails, fetchTypeById, prefetchTypeDetails, operatorsForType, BASELINE_ATTRIBUTES } from "@/lib/api"

// One type, cached + deduped even if called from several components at once.
const person = (await fetchTypeDetails("Person")).data!
const fieldPicker = [...BASELINE_ATTRIBUTES, ...person.attributes]
  .map((a) => ({ key: a.attrKey, label: a.name }))

// Several types in parallel, for a picker that spans more than one type.
const byType = await prefetchTypeDetails(["Person", "Organization", "Insurance"])

// Drive a filter dropdown off the attribute's real type.
const birthDate = person.attributes.find((a) => a.attrKey === "birthDate")!
operatorsForType(birthDate.type) // => ["==","!=","=gt=","=ge=","=lt=","=le=","range"]

// Fallback: resolve by numeric class id (e.g. from a relationship's own target class id).
const byId = (await fetchTypeById(insuranceRel.toClassId)).data!

// Derive grid columns straight from the schema instead of hand-declaring them.
const columns = person.attributes.map((a) => ({
  field: a.attrKey,
  headerName: a.name,
  operators: operatorsForType(a.type),                     // reuse the same type→operator mapping
  options: a.attributeValues?.filter((v) => !v.isDefaultPlaceholder).map((v) => v.name),
}))
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
- A data-fetching/query-cache library (keyed by type name, with an explicit stale time) is a fine
  drop-in for the in-memory cache in step 3 — you don't have to hand-roll the map, just make sure
  concurrent callers for the same type still dedupe.
- Every enumerated attribute's option set can include a hidden platform-default placeholder entry —
  filter it out before presenting choices, whether you're building a form or deriving a grid filter.
- A *relationship's target type's* own value-list metadata is nested one level down (under that
  relationship's own attribute list, not the root type's) — a picker for a related record's field
  needs to look there instead.

## Related

- [query-the-data-graph.md](query-the-data-graph.md) — where the discovered `attrKey`s and
  `filter` get used.
- [relationship-path-building.md](relationship-path-building.md) — turning a discovered
  relationship into a query path.
- [graphql-read-path.md](graphql-read-path.md) — for attributes that live on the relationship/edge
  record itself, which this endpoint doesn't expose.
- [grid-list-views.md](grid-list-views.md) — where schema-derived grid columns get used.
- [../api/README.md](../api/README.md)
