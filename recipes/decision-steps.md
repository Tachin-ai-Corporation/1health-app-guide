# Author conditional branch points in a workflow template

> **Advanced / guardrailed pattern.**

**Use when:** you're building template-authoring tooling that needs conditional branches (a
"decision" step) inside a step tree, or a palette of available step types/decisions for a
template-building UI.
**Routes:** `POST .../workflow-template-step-decision` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-template-step-decision/agents.md) · `GET .../list` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-template-step-decision/list/agents.md) · `GET/PUT/DELETE .../workflow-template-step-decision/{id}` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-template-step-decision/agents.md) · `PUT .../workflow-template-step/{stepId}/decision/{decisionId}` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-template-step/_id_/decision/agents.md) · step-type palette: a normal GraphQL business-type query (n/a — see [graphql-read-path.md](graphql-read-path.md))
**Reference code:** none public — see the Minimal example.
**Seen in:** 1health platform usage (template-authoring tooling)

## Pattern

1. **A decision is a persisted, independently CRUD-able object** — `{ id, name, type, isDefinition,
   conditions[] }` — not just a canvas-only construct. Create, read, update, or delete it on its
   own, separate from any template that currently references it.
2. **`conditions` is opaque from the published docs.** Treat it as a value you round-trip (read →
   modify the pieces you understand → write back the same objects) rather than hand-constructing
   from scratch; verify its shape against a live read first.
3. **Wiring a decision onto a specific step is a separate call** from editing the decision object
   itself: `PUT .../workflow-template-step/{stepId}/decision/{decisionId}`.
4. **Building a step-type palette means two calls run together**: a normal GraphQL business-type
   query (see [graphql-read-path.md](graphql-read-path.md) for the mechanism) filtered by template
   type and active status, for ordinary step types, plus the paginated REST decision list, for
   decision steps — merge both into one offering, tagging each with which node type it becomes on
   the canvas.
5. **Check references before deleting a decision.** Deleting one still wired into a published
   template's branches is a real risk, distinct from deleting an unused one — resolve or warn on
   references the way an admin UI would, rather than deleting unconditionally.

## Minimal example

```ts
import { authFetch, getOneHealthBaseUrl } from "@/lib/auth-client"

const baseUrl = getOneHealthBaseUrl()

// Create a decision — independent of any template that will reference it.
const created = await authFetch(`${baseUrl}/api/v2/health/workflow-template-step-decision`, {
  method: "POST",
  body: JSON.stringify({ name: "Result above threshold?", conditions: [] }),
})
const decision = await created.json()

// Wire it onto a specific step in a draft template.
await authFetch(`${baseUrl}/api/v2/health/workflow-template-step/${stepId}/decision/${decision.id}`, {
  method: "PUT",
  body: JSON.stringify(decision),
})

// List existing decisions — e.g. to check references before deleting one.
const decisions = await (await authFetch(`${baseUrl}/api/v2/health/workflow-template-step-decision/list`)).json()
```

## Gotchas

- **Coerce, don't `===`, any active/enabled flag you read off the step-type catalog** — it has been
  observed serialized as a real boolean in some environments and as the strings `"true"`/`"false"`
  in others.
- **`conditions` items aren't documented** — verify shape against a live response before writing
  new ones by hand; don't assume a shape from this recipe's example.
- **Deleting a decision doesn't check-and-block on its own** — a reference check is your
  responsibility, not something the API enforces for you.

## Related

- [template-versions-draft-publish.md](template-versions-draft-publish.md) — the draft a decision
  step gets wired into.
- [graphql-read-path.md](graphql-read-path.md) — the GraphQL mechanism behind the step-type half of
  the palette query.
- [workflows-journeys-steps.md](workflows-journeys-steps.md) — how an unresolved decision shows up
  on the running-journey side (the step count is unknown until a submit resolves the branch).
- [cohort-filter-conditions.md](cohort-filter-conditions.md) — a decision's conditions are stored
  as the same `DataFilterCondition` records the cohort builder uses. Its catalog and value encoding
  may help you read a decision's `conditions`, but check a live decision before reusing them.
