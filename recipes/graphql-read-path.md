# GraphQL as a third read path

**Use when:** REST genuinely can't answer the question — either you need the scalar attributes
stored on a **relationship/edge record itself** (not the target entity; REST type metadata doesn't
expose these), or the platform models something as a first-class GraphQL business type with its
own query shape (e.g. tags).
**Routes:** `POST /api/graphql` → [agents.md](https://agents.1health.io/public/prod/api/graphql/agents.md)
(a thin stub on the live docs — method + `query`/`variables`/`operationName` only; treat the
examples below as the working reference)
**Reference code:** [`lib/api/type-metadata.ts`](https://github.com/chill-tachin/v0-1h-query-helper/blob/main/lib/api/type-metadata.ts#L163) (introspection) · [`lib/api/tags.ts`](https://github.com/Tachin-ai-Corporation/v0-trc-care-coordinator/blob/main/lib/api/tags.ts#L32) (business-type query)
**Seen in:** query-helper (introspects relationship-record attributes for its query builder),
trc-care-coordinator (queries the `LabelTag` type for bulk tagging)

## Pattern

1. Recognize when `/api/v2/query` and grid can't answer the question: (a) you need attributes
   stored on the join/relationship record itself, which REST type metadata never lists, or (b) the
   platform exposes something as a first-class GraphQL type with its own filter/sort/page shape.
2. POST `{ query, variables }` to `/api/graphql` through the same authenticated call as every other
   request — it's a third path, not a bypass of the trust boundary.
3. For case (a), introspect with `__type(name: "<RelationType>")`, using the relationship's middle
   path segment as `RelationType`; read the `record` field's sub-fields as the join record's own
   attributes, filtering out system fields (`id`, `created`, `updated`, `tags`, …) that aren't real
   app data.
4. For case (b), write a normal GraphQL query against the business type. Its `page`/`sort`/`filter`
   input shape is **type-specific** and unrelated to RSQL — treat each type's shape as its own
   small contract rather than assuming it matches `/query`.
5. Cache introspection/query results the same way you would REST schema metadata — a
   relationship's shape doesn't change at runtime.

## Minimal example

```ts
import { authFetch, getOneHealthBaseUrl } from "@/lib/auth-client"

const SYSTEM_FIELDS = new Set(["id", "name", "created", "updated", "tags", "createdByTenantId"])

/** Scalar attributes stored on a relationship/edge record, via introspection. */
async function fetchRelationAttributes(relationType: string) {
  const baseUrl = getOneHealthBaseUrl()
  const res = await authFetch(`${baseUrl}/api/graphql`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      query: `query($t: String!) { __type(name: $t) { fields { name type { name fields { name type { name } } } } } }`,
      variables: { t: relationType },
    }),
  })
  const { data, errors } = await res.json()
  if (errors?.length) throw new Error(errors.map((e: any) => e.message).join("; "))
  const recordFields = data?.__type?.fields?.find((f: any) => f.name === "record")?.type?.fields ?? []
  return recordFields.filter((f: any) => !SYSTEM_FIELDS.has(f.name))
}

/** A first-class GraphQL business type — its own page/sort/filter shape. */
async function fetchAllTags(tenantId: number) {
  const baseUrl = getOneHealthBaseUrl()
  const res = await authFetch(`${baseUrl}/api/graphql`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      query: `query($page: LabelTagPageInput, $filter: LabelTagFilterInput) {
        LabelTag(page: $page, filter: $filter) { records { id, name }, recordsCount }
      }`,
      variables: { page: { limit: 1000, offset: 0 }, filter: { type: { equal: "Journey" }, createdByTenantId: { equal: tenantId } } },
    }),
  })
  const { data } = await res.json()
  return data?.LabelTag?.records ?? []
}
```

## Gotchas

- **GraphQL failures often arrive as HTTP 200** with an `errors` array in the body, not a non-2xx
  status — check `payload.errors` explicitly. This is why the examples call `authFetch` directly
  and parse `errors` themselves rather than relying on `callApi`'s status-code success/fail split.
- This is a genuinely different request/response shape from `/query` — don't reuse RSQL filter
  strings or the `ROOT.`/edge attribute-prefix helpers here.
- The public route doc is a stub with no schema browser — introspection (case a) or a working
  example from a real app (case b) is often the only way to learn a type's shape.
- A relationship record's field list can drift as the platform evolves — introspecting live
  (rather than hardcoding the field list) is precisely why this path exists.
- Reach for this only when REST can't answer the question — it's a path to know about, not a
  default.

## Related

- [query-the-data-graph.md](query-the-data-graph.md) — the primary read path.
- [schema-discovery.md](schema-discovery.md) — REST schema discovery for entity attributes and
  relationships, which GraphQL introspection complements.
- [../api/README.md](../api/README.md)
