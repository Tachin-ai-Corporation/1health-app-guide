# Define and evaluate a cohort

> **Advanced / guardrailed pattern.**

**Use when:** you need a reusable, named segment of records — combine typed filter atoms into
condition groups, preview the population live, or track its membership over time as periodic
snapshots. Privileged: a population-management admin feature.
**Routes:** `POST/PUT /api/v2/cohort-definition` → [agents.md](https://agents.1health.io/public/prod/api/v2/cohort-definition/agents.md) · `POST …/evaluate` → [agents.md](https://agents.1health.io/public/prod/api/v2/cohort-definition/evaluate/agents.md) · `POST …/evaluate/overview` → [agents.md](https://agents.1health.io/public/prod/api/v2/cohort-definition/evaluate/overview/agents.md) · `PUT …/{id}/activate` → [agents.md](https://agents.1health.io/public/prod/api/v2/cohort-definition/_id_/activate/agents.md) · `GET …/{id}/snapshot/list` → [agents.md](https://agents.1health.io/public/prod/api/v2/cohort-definition/_id_/snapshot/list/agents.md) (plus `disable`, `launch-campaign`, `snapshot/latest/overview`, `snapshot/latest/members`, `snapshot/{id}/export`, `workflow-campaign/{id}/member-coverage` — same collection, see its other headings) · `POST/DELETE /api/v2/filter-group/template` → [agents.md](https://agents.1health.io/public/prod/api/v2/filter-group/template/agents.md) · nested reads via `POST /api/graphql` → [agents.md](https://agents.1health.io/public/prod/api/graphql/agents.md)
**Reference code:** none public — see the Minimal example
**Seen in:** 1health platform usage (a population-management admin feature); not present in any
current example app

## Pattern

1. Build reusable, typed filter atoms first (an attribute path plus the comparison operators valid
   for it) via `filter-group/template`, rather than hand-writing a one-off condition per cohort.
2. Combine atoms into named condition groups, and combine groups with AND/OR, into one cohort
   definition. Read the nested condition tree back through GraphQL — cheap for arbitrary
   self-referential nesting — while every write on the definition itself (create, update, activate,
   disable, evaluate, launch) stays plain REST.
3. Call `evaluate` (a bounded preview of matching records) or `evaluate/overview` (aggregate counts
   only) to see who's in the segment **without persisting anything** — use this to sanity-check a
   definition before activating it.
4. Activate the definition, then materialize membership on a schedule as a **snapshot** — a
   separate, explicit action from evaluation, not something evaluate does implicitly.
5. Treat a snapshot's own `members` read as a capped preview, not an export — it returns a small
   fixed page; use the dedicated `snapshot/{id}/export` route for the full list.
6. To act on a cohort, launch a campaign directly from it (`launch-campaign`) instead of exporting
   ids and hand-building an audience list elsewhere.

## Minimal example

```ts
import { callApi } from "@/lib/api"

// Evaluate before activating — a live preview, nothing persisted yet.
async function previewCohort(definitionId: number) {
  return callApi("cohort/evaluate-overview", "/api/v2/cohort-definition/evaluate/overview", {
    method: "POST",
    body: JSON.stringify({ id: definitionId }),
  })
}

async function activateCohort(definitionId: number) {
  return callApi("cohort/activate", `/api/v2/cohort-definition/${definitionId}/activate`, { method: "PUT" })
}
```

## Gotchas

- The per-attribute filter/sort shape inside a filter-group atom is its own contract, keyed by the
  attribute's value type (date/number/text/boolean/lookup) — it is **not** the RSQL dialect
  `/query` uses; don't port one to the other.
- A snapshot's `members` read is capped to a small fixed page — treat it as a preview and use the
  export route for anything you need in full.
- This whole family is public and documented, but has no known first-party or example-app caller —
  verify request/response shapes on demo before building on them.

## Related

- [query-the-data-graph.md](query-the-data-graph.md)
- [graphql-read-path.md](graphql-read-path.md)
- [bulk-read-and-export.md](bulk-read-and-export.md)
- [../api/README.md](../api/README.md)
