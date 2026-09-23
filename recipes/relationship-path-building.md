# Build a relationship query path

**Use when:** constructing the `key` for a `/query` relationship (or a nested relationship) from
discovered schema metadata — especially when the relationship might be traversed **backwards**.
**Routes:** n/a — client helper (consumes `GET /api/v2/type/key/{typeName}`; see
[schema-discovery.md](schema-discovery.md))
**Reference code:** [`lib/api/schema.ts`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/lib/api/schema.ts#L202) (`getRelationshipTargetType`, `formatRelationshipPath`) · [`lib/utils/type-helpers.ts`](https://github.com/chill-tachin/v0-1h-query-helper/blob/main/lib/utils/type-helpers.ts) (original direction-aware fix)
**Seen in:** query-helper (where the direction bug was found and fixed); baked into the app
template baseline

## Pattern

1. A query relationship path is always three dot-joined segments:
   `{FromType}.{relKey}.{ToType}`.
2. Get `relKey` from the relationship's own metadata (`TypeRelationship.relKey`) — never
   hand-construct it by concatenating type names; it's an opaque platform-assigned string that
   doesn't always look like what you'd guess.
3. Resolve `ToType` by **direction**: a `FORWARD` relationship points at `toBoClassName`; a
   `BACKWARDS` relationship (the edge is defined on the other type, pointing back at yours)
   resolves its target as `fromBoClassName` instead. Getting this backwards silently builds a path
   to the wrong type.
4. Strip whitespace from both type names before using them as path segments — display names
   (`name`, `fromBoClassName`, `toBoClassName`) may contain spaces; query `key`s never do.
5. For multi-hop traversal, repeat the same resolution one level deeper and nest the result inside
   the parent relationship's own `relationships` array.

## Primary vs fallback

- **Primary — eager-load the relationship inside `/query`** (this recipe's path): best when you
  also need the root instance's own attributes, more than one relationship at once, or multi-hop
  nesting, all in the same round trip.
- **Fallback — the dedicated relationship-target endpoint**,
  `POST /api/v2/query/{typeKey}/{instanceId}?relKey=…&targetTypeKey=…` (documented on the
  [`/v2/query` page](https://agents.1health.io/public/prod/api/v2/query/agents.md)): switch here
  when you already have the instance id and want just one relationship's targets, with their own
  `page`/`size`/`orderBy`/`searchText` and a standard page envelope — a natural fit for powering a
  "records already linked to this one" list or picker. Its `filterBy` is equality-only (a plain
  key→value map, not RSQL), and `includeRelAttributes` optionally attaches the edge's own attributes
  to each row — drop back to the primary path the moment you need `contains`/range/"one of"
  filtering on the target. Confirmed against the demo environment: rows carry `attributes` +
  `relAttributes`, `searchText` matches on the target's name, `filterBy: { lastName: "…" }` does an
  exact match, and `orderBy: { id: "DESC" }` is accepted.

## Minimal example

```ts
import { fetchTypeDetails, getRelationshipTargetType, formatRelationshipPath, runQueryRows } from "@/lib/api"

const source = (await fetchTypeDetails("Person")).data!
const rel = source.relationships.find((r) => r.name === "Insurance")!

const targetType = getRelationshipTargetType(rel)          // honors FORWARD/BACKWARDS
const path = formatRelationshipPath("Person", rel.relKey, targetType)
// FORWARD example  => "Person.PersonHasInsurance.Insurance"
// BACKWARDS example => "Person.PersonIsMemberOfWorkflowTemplate.WorkflowTemplate"
//   (target resolves to fromBoClassName, not toBoClassName, because the edge is
//   defined on WorkflowTemplate pointing at Person)

const rows = await runQueryRows({
  key: "Person",
  attributes: ["id"],
  relationships: [{ key: path, attributes: ["id"] }],
})
```

## Gotchas

- **The #1 correctness trap:** for a `BACKWARDS` relationship, the target type is
  `fromBoClassName`, not `toBoClassName` — swapping this produces a path that queries the wrong
  type, or one that 400s.
- Never fabricate `relKey` by concatenating type names — it's a platform-assigned string (e.g.
  `WorkflowTemplateStepIsRootOfWorkflowTemplate`) that only sometimes matches that pattern.
- The `relKey` for the forward and backward traversal of the *same edge* can differ (`relKey` vs
  `reverseRelKey`) — resolve from the relationship object you found on the type you're starting
  from, not its inverse.
- Type names in `fromBoClassName`/`toBoClassName` may contain spaces (display formatting) —
  always strip them; the helper does this for you, but a hand-rolled path builder easily forgets.
- The relationship-target endpoint's `filterBy` only does equality — even if you thread an
  operator-tagged value through a shared filter-string parser, only the equality split reaches the
  server; the operator itself is silently discarded.

## Related

- [schema-discovery.md](schema-discovery.md) — where `relKey`, `direction`, `fromBoClassName`, and
  `toBoClassName` come from.
- [query-the-data-graph.md](query-the-data-graph.md) — where the finished path is used, in
  `relationships[].key`.
- [choose-a-read-path.md](choose-a-read-path.md) — deciding between this and the other read paths.
- [../api/README.md](../api/README.md)
