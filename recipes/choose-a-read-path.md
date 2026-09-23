# Choose a read path

**Use when:** you're about to fetch data from 1health and need to pick the right mechanism before
writing any code — one filtered projection, a relationship's children, a screen's list view, and a
tiny picker all call for different tools, and picking the wrong one by default costs you later.
**Routes:** `POST /api/v2/query` → [agents.md](https://agents.1health.io/public/prod/api/v2/query/agents.md) · `GET /api/v2/query/{typeKey}` → [agents.md](https://agents.1health.io/public/prod/api/v2/query/agents.md) · `POST /api/v2/query/{typeKey}/{instanceId}` → [agents.md](https://agents.1health.io/public/prod/api/v2/query/agents.md) (all three documented on the same page, under separate headings) · `POST /api/v3/health/grid/<view>` → [agents.md](https://agents.1health.io/public/prod/api/v3/health/grid/journey/agents.md) (per view — see the [manifest](https://agents.1health.io/public/prod/api/manifest.md) for the full list) · `POST /api/graphql` → [agents.md](https://agents.1health.io/public/prod/api/graphql/agents.md)
**Reference code:** [`lib/api/query.ts`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/lib/api/query.ts) (the generic query and its path-based variants) · [`lib/api/grid.ts`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/lib/api/grid.ts) (the grid path)
**Seen in:** every example app uses each mechanism individually; building a screen around a
pluggable fetch strategy (so swapping which one backs it later isn't a rewrite) is 1health platform usage

## Pattern

1. Decide by what you already have and what shape you need — this is a choice, not a default to
   fall into.
2. An arbitrary projection, an RSQL filter, or more than one relationship read together → the
   generic query, `POST /v2/query` (see [query-the-data-graph.md](query-the-data-graph.md)).
3. A small reference-type lookup for a picker — just `id`+name, `page`/`limit`/`search`, no real
   filter → `GET /v2/query/{typeKey}`.
4. You already hold one instance id and need only one relationship's targets, with their own
   paging/search/sort → the relationship-target endpoint,
   `POST /v2/query/{typeKey}/{instanceId}?relKey=…&targetTypeKey=…` (see
   [relationship-path-building.md](relationship-path-building.md)'s Primary vs fallback).
5. A server-defined table/list screen that already has a matching view → the grid engine (see
   [grid-list-views.md](grid-list-views.md)).
6. A platform-native GraphQL business type, or attributes stored on the relationship/edge record
   itself → GraphQL (see [graphql-read-path.md](graphql-read-path.md)).
7. Treat v1 as the basement layer beneath every wrapper above — reach for it only for a raw
   primitive that genuinely has no wrapper (rare; see
   [api-versions-and-layers.md](api-versions-and-layers.md) and
   [boi-instance-attribute-write.md](boi-instance-attribute-write.md) for the one confirmed case).

## Primary vs fallback

- **Primary — the generic query (`POST /v2/query`):** the default for an arbitrary
  projection/filter/multi-relationship read, and the right choice whenever you're not sure which
  of the below fits better.
- **Fallback — `GET /v2/query/{typeKey}`:** swap in for a lightweight picker (a dropdown of names)
  where you don't need a real filter — cheaper to call, but only `page`/`limit`/`search`, no RSQL.
- **Fallback — the relationship-target endpoint:** swap in when you already hold one instance id
  and want just one relationship's targets with their own `page`/`size`/`orderBy`/`searchText` —
  its `filterBy` is equality-only, so drop back to the primary the moment you need
  `contains`/range/"one of" filtering on the target.
- **Fallback — the grid engine:** swap in the moment a ready-made view exists for the screen you're
  building — pre-flattened and already paginated the way a list UI expects.
- **Fallback — GraphQL:** swap in for a platform-native GraphQL type, or when you need an edge
  record's own attributes, which no REST path exposes. It's a first-class list source for that
  case, not only an escape hatch — but it's still its own contract (type-specific page/sort/filter
  shapes, not RSQL), so don't reach for it once a REST path already fits.
- **Fallback (rare) — v1 primitives:** reach for it only when nothing above exposes the raw
  primitive you need.

## Minimal example

```ts
// A decision helper — not a real endpoint, just the shape of the choice.
type ReadPath = "query" | "typeaheadQuery" | "relationshipQuery" | "grid" | "graphql"

function chooseReadPath(need: {
  hasInstanceId?: boolean
  needsOneRelationshipOnly?: boolean
  matchingGridView?: string
  needsEdgeAttributesOrNativeType?: boolean
}): ReadPath {
  if (need.needsEdgeAttributesOrNativeType) return "graphql"
  if (need.matchingGridView) return "grid"
  if (need.hasInstanceId && need.needsOneRelationshipOnly) return "relationshipQuery"
  return "query" // the generic projection/filter/relationship read — the default
}
```

## Gotchas

- The bare `/v2/query` and its two path-based variants are documented on the *same* agents.md page
  under separate headings — don't assume only the bare form is real just because it's the one most
  examples use.
- Neither `GET /v2/query/{typeKey}` nor the relationship-target endpoint speaks RSQL — the moment
  you need `contains`/range/"one of these" filtering, go back to the generic query.
- A generic list/table UI component is worth building around a pluggable fetch strategy from day
  one (GraphQL query / REST callback / static array) — swapping which 1health mechanism backs a
  screen then doesn't mean rewriting the screen.
- Picking a mechanism isn't permanent — the same screen can start on the generic query and move to
  a grid view later without changing anything else about it, as long as the UI layer doesn't
  hardcode the fetch shape.

## Related

- [query-the-data-graph.md](query-the-data-graph.md)
- [relationship-path-building.md](relationship-path-building.md)
- [grid-list-views.md](grid-list-views.md)
- [graphql-read-path.md](graphql-read-path.md)
- [api-versions-and-layers.md](api-versions-and-layers.md)
- [../api/README.md](../api/README.md)
