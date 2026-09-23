# Patient grid + demographic find

**Use when:** you need to check whether a matching patient already exists (before creating a new
one) or need a filterable, paginated patient list — as opposed to reading one patient you already
have the id for.
**Routes:** `POST /v3/health/grid/patient` → [agents.md](https://agents.1health.io/public/prod/api/v3/health/grid/patient/agents.md) · `GET /v3/patient/find` → [agents.md](https://agents.1health.io/public/prod/api/v3/patient/find/agents.md) · `POST /v2/health/organization/patient` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/organization/patient/agents.md)
**Reference code:** [`lib/api/patient.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/api/patient.ts) (`fetchPatientGrid`, `findPatients`) · [`lib/patient-find.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/patient-find.ts) (query builder)
**Seen in:** patient-vault

## Pattern

1. **Pick the right endpoint for the job — three exist.** The **grid** endpoint is a browsable,
   paginated, sortable list (same family as any other grid view) — use it to populate a patients
   table/search screen. A simple **full-text search** (`POST /v2/health/organization/patient`,
   query params `fullTextSearchOnPerson`/`page`/`size`) is a single free-text term scoped to your
   org — use it for an ordinary typeahead where duplicate detection isn't the goal. The **find**
   endpoint is a scored demographic match — use it to answer "does a patient like this already
   exist" before you create one. See Primary vs fallback below for which to reach for by default.
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
5. **After a search turns up no acceptable match, create the patient via v3**
   ([patient-crud.md](patient-crud.md)) rather than looping into another search variant hoping for
   a different answer — then confirm the new patient is attached to your organization
   ([deferred-record-creation.md](deferred-record-creation.md) has the check and the fallback).

## Primary vs fallback

- **Primary — scored find (`GET /v3/patient/find`):** reach for this whenever the search outcome
  decides whether to create a new patient — it's what confidence-scores a candidate match instead
  of just returning text hits.
- **Fallback — full-text search (`POST /v2/health/organization/patient`) or the patient grid:** a
  single free-text term or a browsable table, for an ordinary "search patients in my org" list or
  typeahead where deduplication isn't the goal. A simpler lookup can look sufficient for a
  create-or-match decision, but only the scored find is built to answer that question with
  confidence — don't substitute the simpler endpoints for that job just because they're easier to
  call.

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
    "person/find", `/api/v3/patient/find?${buildFindQuery(criteria)}`,
  )
  return (res.data?.patients ?? []).sort((a, b) => b.score - a.score) // never assume server-sorted
}

export async function fetchPatientGrid(page = 0, size = 25, lastNameContains?: string) {
  const filterBy = lastNameContains
    ? [{ key: "lastName", operator: "contains", value: lastNameContains }]
    : []
  return callApi("person/grid", `/api/v3/health/grid/patient?page=${page}&size=${size}`, {
    method: "POST",
    body: JSON.stringify({ filterBy, orderBy: [{ key: "created", order: "DESC" }] }),
  })
}

// FALLBACK — a plain, org-scoped typeahead (one free-text term, no scoring).
export async function searchPatientsByText(term: string, page = 0, size = 25) {
  const res = await callApi<{ data: Array<{ id: number; firstName: string; lastName: string }> }>(
    "person/fullTextSearch",
    `/v2/health/organization/patient?fullTextSearchOnPerson=${encodeURIComponent(term)}&page=${page}&size=${size}`,
    { method: "POST" },
  )
  return res.data?.data ?? []
}
```

## Gotchas

- **Find is a fuzzy, scored match, not an identity check** — a top-scored candidate is still a
  suggestion; deciding "same person" is a product/clinical decision, not a platform guarantee.
- **An empty-string query param is not the same as an omitted one** on this endpoint — omit blank
  criteria rather than sending `firstName=`.
- **A grid row is a different, flatter shape than the full patient record** — map it separately
  instead of forcing it through your record mapper.
- **The three endpoints don't share a calling convention** — grid and full-text search are POST
  with filters/criteria in the body or query string; find is GET with criteria in the query string.
- **An empty `fullTextSearchOnPerson` term isn't the same as omitting the call** — only call the
  full-text search once the caller has actually typed something.

## Related

- [patient-crud.md](patient-crud.md) — the full record shape once you have an id.
- [grid-list-views.md](grid-list-views.md) — the general grid pattern this specializes.
- [query-the-data-graph.md](query-the-data-graph.md)
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
