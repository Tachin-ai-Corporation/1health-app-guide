# Patient grid + demographic find

**Use when:** you need to check whether a matching patient already exists (before creating a new
one) or need a filterable, paginated patient list — as opposed to reading one patient you already
have the id for.
**Routes:** `POST /v3/health/grid/patient` → [agents.md](https://agents.1health.io/public/prod/api/v3/health/grid/patient/agents.md) · `GET /v3/patient/find` → [agents.md](https://agents.1health.io/public/prod/api/v3/patient/find/agents.md)
**Reference code:** [`lib/api/patient.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/api/patient.ts) (`fetchPatientGrid`, `findPatients`) · [`lib/patient-find.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/patient-find.ts) (query builder)
**Seen in:** patient-vault

## Pattern

1. **Pick the right endpoint for the job.** The **grid** endpoint is a browsable, paginated,
   sortable list (same family as any other grid view) — use it to populate a patients table/search
   screen. The **find** endpoint is a scored demographic match — use it to answer "does a patient
   like this already exist" before you create one.
2. **Build the find query from whatever demographic fields you have** (firstName/lastName/dob/
   sexAtBirth); omit blank fields from the query string rather than sending them empty — an
   empty-string param can behave like "match everything" on a fuzzy matcher. Always send the
   boolean `exact` flag explicitly.
3. **Treat the response as ranked candidates, not an answer.** Each candidate carries a `score` and
   a `matchedOn` list of which fields matched; sort by score client-side (don't assume the server
   pre-sorts), and let a human — or an explicit, documented threshold — decide whether a
   high-scoring candidate is "the same person." Never auto-merge on a match.
4. **Map grid rows with their own mapper, not your full-record mapper.** A grid row is a flatter,
   different DTO than the full record (e.g., race/ethnicity may come back as plain scalar strings
   instead of the coded objects a full fetch returns) — treat it as a distinct read model, good
   enough to render a list, and fetch the full record only on drill-in.

## Minimal example

```ts
import { callApi } from "@/lib/api"

interface FindCriteria {
  firstName?: string; lastName?: string; dob?: string; sexAtBirth?: string; exact: boolean
}

function buildFindQuery(c: FindCriteria): string {
  const params = new URLSearchParams()
  if (c.firstName?.trim()) params.set("firstName", c.firstName.trim())
  if (c.lastName?.trim()) params.set("lastName", c.lastName.trim())
  if (c.dob) params.set("dob", c.dob)
  if (c.sexAtBirth) params.set("sexAtBirth", c.sexAtBirth)
  params.set("exact", String(c.exact))
  return params.toString()
}

export async function findCandidates(criteria: FindCriteria) {
  const res = await callApi<{ patients: Array<{ id: number; score: number; matchedOn: string[] }> }>(
    "person/find", `/v3/patient/find?${buildFindQuery(criteria)}`,
  )
  return (res.data?.patients ?? []).sort((a, b) => b.score - a.score) // never assume server-sorted
}

export async function fetchPatientGrid(page = 0, size = 25, lastNameContains?: string) {
  const filterBy = lastNameContains
    ? [{ key: "lastName", operator: "contains", value: lastNameContains }]
    : []
  return callApi("person/grid", `/v3/health/grid/patient?page=${page}&size=${size}`, {
    method: "POST",
    body: JSON.stringify({ filterBy, orderBy: [{ key: "created", order: "DESC" }] }),
  })
}
```

## Gotchas

- **Find is a fuzzy, scored match, not an identity check** — a top-scored candidate is still a
  suggestion; deciding "same person" is a product/clinical decision, not a platform guarantee.
- **An empty-string query param is not the same as an omitted one** on this endpoint — omit blank
  criteria rather than sending `firstName=`.
- **A grid row is a different, flatter shape than the full patient record** — map it separately
  instead of forcing it through your record mapper.
- **The two endpoints don't share a calling convention** — grid is POST with filters/sort in the
  body; find is GET with criteria in the query string.

## Related

- [patient-crud.md](patient-crud.md) — the full record shape once you have an id.
- [grid-list-views.md](grid-list-views.md) — the general grid pattern this specializes.
- [query-the-data-graph.md](query-the-data-graph.md)
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
