# Link and unlink two instances

**Use when:** two instances already exist and you need to connect or disconnect them under a named
relationship — without a typed create-with-relationship call, and without recreating either
instance.
**Routes:** `POST /api/v2/relationship/create` → [agents.md](https://agents.1health.io/public/prod/api/v2/relationship/create/agents.md) · `DELETE /api/v2/relationship/delete` → [agents.md](https://agents.1health.io/public/prod/api/v2/relationship/delete/agents.md)
**Reference code:** none public — see the Minimal example
**Seen in:** documented in 1health's published API docs; not exercised by any example app yet —
treat it as lightly-tested and verify the exact behavior on demo before you rely on it

## Pattern

1. Resolve `relKey` the same way you would for any query relationship — from the source type's
   schema metadata (see [schema-discovery.md](schema-discovery.md) /
   [relationship-path-building.md](relationship-path-building.md)) — never hand-type it.
2. Create one or many edges in a single call: one `fromInstanceId`, an array of `toInstanceIds`,
   the `relKey`, and an optional list of relationship (edge) attributes applied to every edge
   created.
3. Delete with the same selector shape — `fromInstanceId` + `toInstanceIds` + `relKey`. Deletion is
   soft only; there's no documented hard-delete counterpart for a relationship.
4. Prefer one bulk call over looping single-target creates or deletes — linking one instance to
   many targets is a genuine bulk operation here, not N round trips.
5. Because this route is public but lightly exercised, re-read the relationship afterward (eager-
   loaded in `/query`, or via the relationship-target endpoint) to confirm the edge landed the way
   you expect, rather than trusting a 200 alone the first few times you use it.

## Minimal example

```ts
import { callApi } from "@/lib/api"

/** Link one instance to one or many targets under a named relationship, in one call. */
async function linkInstances(fromInstanceId: number, toInstanceIds: number[], relKey: string) {
  return callApi("relationship/create", "/api/v2/relationship/create", {
    method: "POST",
    body: JSON.stringify({ fromInstanceId, toInstanceIds, relKey }),
  })
}

/** Unlink the same selector — soft-deletes only the matching edges. */
async function unlinkInstances(fromInstanceId: number, toInstanceIds: number[], relKey: string) {
  return callApi("relationship/delete", "/api/v2/relationship/delete", {
    method: "DELETE",
    body: JSON.stringify({ fromInstanceId, toInstanceIds, relKey }),
  })
}
```

## Gotchas

- This route is documented and public, but has no known first-party or example-app caller —
  confirm the exact request/response shape (including error behavior for a bad `relKey` or a
  duplicate edge) on demo before shipping it.
- Deletion is soft only — there's no documented hard-delete for a relationship, unlike files or a
  whole instance.
- `relKey` is the same opaque, platform-assigned string used everywhere else in query
  relationships — resolve it from schema metadata, don't guess it from the two type names.
- One call applies the same optional relationship attributes to every target in `toInstanceIds` —
  if different targets need different edge attribute values, that needs one call per distinct set.

## Related

- [relationship-path-building.md](relationship-path-building.md)
- [schema-discovery.md](schema-discovery.md)
- [query-the-data-graph.md](query-the-data-graph.md)
- [../api/README.md](../api/README.md)
