# Model a state machine in customData

> **Prefer the native workflow engine (journey → steps) as your first-order state machine.** Use customData-as-state-machine only when the workflow template can't represent the state you need — e.g. the template defines no/empty dynamic step-fields (the situation this pattern came from).

**Use when:** a step's (or its journey's) own dynamic fields can't represent the state you need to track, so the state has to live somewhere else — and you need both "this step's own current state" and a cheap way to list many instances without re-reading every step.
**Routes:** read via `POST /api/v2/query` (project `customData` on the step/journey instances) · write via `POST /api/v2/data/custom-data/bulk` → [agents.md](https://agents.1health.io/public/prod/api/v2/data/custom-data/bulk/agents.md)
**Reference code:** [`lib/expertdx/case.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/lib/expertdx/case.ts#L389) (`writeNamespaced`) · [`rebuildJourneyIndex`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/lib/expertdx/case.ts#L722)
**Seen in:** ExpertDx (the one example app whose workflow template ships with zero dynamic step-fields, forcing the whole case lifecycle into customData)

## Pattern

1. Pick one namespace key for your app's state on each involved instance (e.g. `appData.<appId>`), so a shallow `APPEND` of that one key round-trips your whole object safely.
2. Treat each **step's own** `customData` as the source of truth for what happened at that step. Read it fresh rather than trusting in-memory state — another actor (a different plane of the same app, a manual fix) may have changed it.
3. Maintain a small denormalized **index** — a summary object (phase, a few display fields, flags) — on the **parent** instance (the journey), updated whenever a step's data changes meaningfully. This makes list/dashboard reads cheap: one query over the parent type returns every row's status without fetching each step.
4. Because the index is a cache, derive it with a **pure function** over the authoritative step data (e.g. `derivePhase(steps)`), and expose a `rebuild` operation that recomputes and rewrites it from scratch. Call `rebuild` whenever the index might have drifted — after a failed write, a manual data fix, or a template change.
5. Every write is read → merge → write: read the current namespaced object, shallow-merge your patch into it in memory, then `APPEND` the whole merged object back. Never patch a nested key directly (see [read-write-custom-data.md](read-write-custom-data.md)).
6. Guard which phase/step a given caller is allowed to write in code, not just in the UI — a state machine is only as trustworthy as its transition guard.

## Minimal example

```ts
import { readCustomData, mergeCustomData, appData } from "@/lib/api"

const NS = "appData"

// A step's own customData is authoritative for that step's outcome.
async function writeStepOutcome(appId: string, stepInstanceId: number, patch: Record<string, unknown>) {
  return mergeCustomData("Step", stepInstanceId, appData(appId, patch))
}

interface CaseIndex {
  phase: "draft" | "in_review" | "completed"
  patientDisplay?: string
  attention?: "info_requested" | null
}

// Pure derivation over authoritative step data — this is what `rebuild` calls.
function derivePhase(steps: Record<string, { status: string }>): CaseIndex["phase"] {
  if (steps["Final review"]?.status === "Completed") return "completed"
  if (steps["Intake"]?.status === "Completed") return "in_review"
  return "draft"
}

// Recompute the index from authoritative data and write it back — call after
// any step write, and whenever the index might have drifted.
async function rebuildIndex(appId: string, journeyId: number, steps: Record<string, { status: string }>) {
  const current = await readCustomData("Journey", journeyId)
  const index: CaseIndex = { ...(current[NS] as any)?.[appId], phase: derivePhase(steps) }
  await mergeCustomData("Journey", journeyId, appData(appId, index))
  return index
}
```

## Gotchas

- The index is a **cache, not a fact** — a write can fail, a step can change outside your app, or your derivation logic can evolve. Keep the pure `derive*` function around so `rebuild` can always recover it, rather than trusting whatever the index currently says.
- Step instance ids are per-parent — resolve name → id fresh for each journey; never cache a step id across journeys.
- `customData` is schemaless and long-lived: read defensively, since blobs written by an earlier version of your app are still out there.
- A fast-changing field (a live counter/ticket) that races the index update should get its own top-level key, not live inside the index object, or a concurrent write to one can clobber the other's `APPEND`.
- The platform has no compare-and-set — two concurrent writers to the same instance can still clobber each other's fields. Recover with the same `rebuild` operation rather than trying to prevent every race.

## Related

- [read-write-custom-data.md](read-write-custom-data.md) — the shallow-`APPEND` mechanics this pattern builds on.
- [write-safety-and-fail-closed.md](write-safety-and-fail-closed.md) — never let a failed read collapse into "treat as empty" before a write.
- [audit-trail-in-custom-data.md](audit-trail-in-custom-data.md) — a sibling pattern for an append-only log instead of current-state.
- [workflows-journeys-steps.md](workflows-journeys-steps.md) — the native step/status model this pattern is an escape hatch from.
