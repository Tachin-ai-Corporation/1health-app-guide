# Query the data graph

**Use when:** you need to read one or more entities — optionally with their related entities —
with a specific projection and filter. (For a server-defined table/list view, use the grid recipe
instead.)
**Routes:** `POST /api/v2/query` → [agents.md](https://agents.1health.io/public/prod/api/v2/query/agents.md)
**Reference code:** [`lib/api/query.ts`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/lib/api/query.ts)
**Seen in:** every example app (it's the core read engine)

## Pattern

1. **Pick the type** you want by its string `key` (e.g. `"Person"`). Know it up front or discover
   it at runtime.
2. **Project** only the `attributes` you need. Include `"customData"` if you need app fields.
3. **Filter** with an RSQL string — build it with the helpers so quoting is correct
   (`and` joins with `;`, `or` joins with `,`).
4. **Eager-load relations** (optional) via `relationships`, keyed `SourceType.EdgeName.TargetType`;
   prefer one query with relationships over N follow-up calls.
5. **Extract values** with the helpers — responses are prefixed, so never read
   `attributes["firstName"]` directly.
6. **Paginate** by looping `offset` until a short page (there is no reliable total).

## Minimal example

```ts
import { runQueryRows, and, eq, ilike, findAttr, getRelated, getRelatedAttr, parseCustomData } from "@/lib/api"

// Person(s) in an org whose last name matches a term, plus their insurance.
const rows = await runQueryRows({
  key: "Person",
  attributes: ["id", "firstName", "lastName", "customData"],
  filter: and(eq("organizationId", orgId), ilike("lastName", term)),
  relationships: [
    { key: "Person.PersonHasInsurance.Insurance", attributes: ["id", "memberIdNumber"] },
  ],
  limit: 50,
})

for (const row of rows) {
  const name = findAttr<string>(row, "firstName")               // prefix-agnostic read
  const app  = parseCustomData(findAttr(row, "customData"))     // may arrive as a string
  for (const ins of getRelated(row, "Person.PersonHasInsurance.Insurance")) {
    const member = getRelatedAttr<string>(ins, "PersonHasInsurance", "Insurance", "memberIdNumber")
  }
}
```

RSQL cheat sheet (see `query.ts` for the full set): `eq/neq`, `gt/ge/lt/le`, `range`, `inList`,
`ilike` (case-insensitive contains), `like`, `re` (regex), JSON ops (`hasKey`, `pathMatches`, …).
Combine with `and(...)` / `or(...)`.

## Gotchas

- **Root attributes come back prefixed `ROOT.<Type>.<attr>`**; related attributes as
  `<Edge>.<Target>.<attr>` (leading source segment dropped). Use `getRootAttr`/`getRelatedAttr`, or
  `findAttr` (suffix match) when unsure — prefix formatting isn't perfectly consistent.
- **`customData` may be a JSON string** — always `parseCustomData`.
- **No reliable `totalElements`/`lastPage`** — detect the end by `rows.length < pageSize`
  (`runQueryAll` does this).
- **Server-side filters on deeply-nested `customData` can be unreliable** — re-validate client-side
  when correctness matters.
- **A journey instance is typed `"WorkflowTemplate"`** in the query engine (same name as its
  definition) — distinguish by attributes present, not type name.
- **A third read path exists** (`POST /api/graphql`) with its own shape — don't conflate it with `/query`.

## Related

- [read-write-custom-data.md](read-write-custom-data.md) — the `customData` you project here.
- Grid/list views → [grid-list-views.md](grid-list-views.md).
- Schema discovery (find types & attributes at runtime) → [schema-discovery.md](schema-discovery.md).
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md).
