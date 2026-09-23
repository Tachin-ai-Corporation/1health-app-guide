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

### Fuller operator reference

| Helper | RSQL token | Meaning | Confirmed |
|---|---|---|---|
| `eq` / `neq` | `==` / `!=` | equals / not equals | public docs |
| `lt` / `le` / `gt` / `ge` | `=lt=` / `=le=` / `=gt=` / `=ge=` | less/greater than (or equal) | public docs |
| `inList` / (not-in) | `=in=` / `=out=` | value is one of / none of a list — text attributes; on the numeric `id` it 400s ("not of type: Long"), so use `id==a,id==b` (confirmed on demo) | public docs |
| `like` / `ilike` | `=like=` / `=ilike=` | substring / case-insensitive substring | platform usage — not in the public operator list |
| `re` / (negated) | `=re=` / `=nre=` | regex match / non-match | platform usage — not in the public operator list |
| (contains-ish) | `=c=` / `=nc=` / `=ic=` / `=inc=` | contains / not-contains, case-sensitive / -insensitive | platform usage — not in the public operator list |

JSON/JSONB — the public docs list raw Postgres-style tokens; platform usage elsewhere favors named
equivalents for the same ideas:

| Token | Meaning | Confirmed |
|---|---|---|
| `@>` / `<@` | JSON containment (left contains right / right contains left) | public docs |
| `?` / `?\|` / `?&` | has key / has any of these keys / has all of these keys | public docs |
| `->` / `->>` | get JSON field (as JSON / as text) | public docs |
| `#>` / `#>>` | get at JSON path (as JSON / as text) | public docs |
| `=hk=` / `=hak=` / `=haak=` | has key / has any key / has all keys | platform usage — not in the public operator list |
| `=jpe=` / `=jpm=` | JSON path exists / JSON path matches | platform usage — not in the public operator list |

`=c=` means opposite things depending on the attribute's type — text substring containment vs. JSON
structural containment — same token, different semantics.

A **second, independent filter mechanism** lives on the same request: a sibling `customData:
{ filters }` object (confirmed as a field on the request body in the public docs, though its
detailed shape isn't spelled out there) addresses **typed** custom fields — see
[typed-custom-field-definitions.md](typed-custom-field-definitions.md) — by their camelCase
`fieldKey`, not by RSQL. Per platform usage: it has its own narrower operator subset (`==, !=, =gt=,
=ge=, =lt=, =le=, =in=, =out=`, plus text-only contains variants) and **requires an application
context** to be present on the call at all. Quoting differs too: the typed-field filter requires
quoting any spaced value with *every* operator (including inside an "is one of" list), while the
plain `filter` string only auto-quotes after `==`. An instance with no custom data stored at all
matches nothing for a typed-field filter — including a negated one — so a `!=` check won't behave
the way you'd expect against a "never set" instance.

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
- **Two different "customData" filters exist on this same call** — the schemaless `filter` string's
  JSON operators target the raw blob; the sibling `customData: { filters }` object targets **typed**
  fields by `fieldKey` and needs an app context. Don't conflate them.

## Related

- [read-write-custom-data.md](read-write-custom-data.md) — the `customData` you project here.
- [typed-custom-field-definitions.md](typed-custom-field-definitions.md) — the typed fields the
  second `customData: { filters }` object addresses.
- Grid/list views → [grid-list-views.md](grid-list-views.md).
- Schema discovery (find types & attributes at runtime) → [schema-discovery.md](schema-discovery.md).
- Deciding which read mechanism to use at all → [choose-a-read-path.md](choose-a-read-path.md).
- Paging to exhaustion and ordering results → [query-pagination-and-sorting.md](query-pagination-and-sorting.md).
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md).
