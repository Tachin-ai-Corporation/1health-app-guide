# Model and advance a workflow: campaigns, journeys & steps

**Use when:** you need to represent a multi-step business process (an application, a case, a
document exchange, an approval chain, …) as a **workflow**, and advance a running instance of it
one step at a time.
**Routes:** `POST /api/v2/journey` (create) → [agents.md](https://agents.1health.io/public/prod/api/v2/journey/agents.md) · `GET .../journey/{id}/steps` → [agents.md](https://agents.1health.io/public/prod/api/v2/journey/_id_/steps/agents.md) · `GET .../step/{stepId}/info` → [agents.md](https://agents.1health.io/public/prod/api/v2/journey/_id_/step/_stepId_/info/agents.md) · `POST .../step/{stepId}/submit` → [agents.md](https://agents.1health.io/public/prod/api/v2/journey/_id_/step/_stepId_/submit/agents.md)
**Reference code:** [`lib/api/journey.ts`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/lib/api/journey.ts) · [`lib/api/journey-step.ts`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/lib/api/journey-step.ts)
**Seen in:** every example app — the core workflow engine

## Pattern

1. **Know your hierarchy.** A **Campaign** is the handle you start journeys from; it points at a
   **WorkflowTemplate** (the step-tree definition). A **Journey** is a running INSTANCE of that
   template, started from a campaign. A **Step** is one node in the instance's step sequence.
2. **Start a journey** from an already-resolved campaign id: `POST /journey` with `{ campaignId }`.
   Optionally seed and submit the first step inline (`submitSteps: [{ key, data }]`) to skip a
   round trip.
3. **Treat the journey as a state machine, not a graph.** Steps are a (possibly branching)
   sequence. Fetch its steps and find the one that's currently actionable (the one flagged
   submittable) rather than assuming a fixed index.
4. **Load that step's live schema + values** before rendering or submitting — see
   [dynamic-step-fields.md](dynamic-step-fields.md) for resolving its fields generically.
5. **Submit the actionable step** using the recipe that matches its shape (below). **A valid
   submit both saves the data AND advances the journey — there is no separate "complete" call.**
6. **Re-fetch to observe the advance.** Submits don't optimistically update anything client-side.
   For synchronous steps, re-fetch steps/step-info immediately; for steps that trigger async
   server-side work (e.g. document generation), poll a lightweight sentinel (often a `customData`
   flag) until it flips, then refetch once.
7. **Repeat until the journey reaches a terminal status.**

### Submitting a step — three recipes

Pick by what the step's schema looks like:

- **A — plain JSON** (built-in steps: entity pickers, id entry): a fixed, well-known body, no
  dynamic-field wrapping.
- **B — dynamic fields, no file** (the common case): **echo every field back, mutating only the
  one(s) you changed** — read-all → mutate → write-all, never a partial patch. Sent as
  `multipart/form-data` with **`?attachment` required even when there is no file** — it's what
  tells the server to parse the body as the dynamic-fields shape.
- **C — dynamic fields + a file**: same echo-all body, plus the file in its own multipart part
  tagged with the file field's id. Removing an uploaded file reuses the same endpoint
  (delete-by-flag).

## Minimal example

```ts
import {
  createJourney, fetchJourneySteps, findActionableStep, fetchStepInfo,
  submitStepFields, resolveFieldsByLabel, getDynamicFields,
} from "@/lib/api"

// 1. Start a journey from a resolved campaign.
const created = await createJourney(campaignId)
const journeyId = created.data!.id

// 2. Find the currently-actionable step.
const steps = await fetchJourneySteps(journeyId)
const step = findActionableStep(steps.data)!          // the step flagged submittable

// 3. Load its live fields.
const info = await fetchStepInfo(journeyId, step.id)
const fields = getDynamicFields(info.data?.configuration)

// 4. Submit (Recipe B) — resolve the field(s) you're changing by label, echo the rest.
const ids = resolveFieldsByLabel(fields, { note: "Clinical Note" })
await submitStepFields(journeyId, step.id, fields, { [ids.note!]: "All clear" })

// 5. Re-fetch to see the journey's new actionable step.
const next = await fetchJourneySteps(journeyId)
```

## Gotchas

- **A journey is typed the same as its definition** in the generic query engine (both come back as
  `"WorkflowTemplate"`) — distinguish by the attributes present (`workflowCampaignId`, `status`),
  never by type name.
- **No separate "complete" call.** A valid submit of the actionable step marks it done and
  advances the journey server-side; don't look for (or build) a second endpoint.
- **Forgetting to pass the full fields array is the most common bug** — Recipe B/C require echoing
  every field you fetched, mutating only the changed one(s); a partial body silently drops the rest.
- **`?attachment` is required on step-submit even without a file** (Recipe B) — omitting it sends
  the wrong body shape.
- **Steps are a sequence, not a free graph** — branching templates need their own traversal
  (inspect `key`/`metadata.nodeType`); don't build UI that jumps to an arbitrary step.
- **Journey-level operations take array-wrapped bodies** even for a single id (assign/unassign
  users, bulk status) — a common shape mismatch.

## Related

- [dynamic-step-fields.md](dynamic-step-fields.md) — resolving a step's field ids before submit.
- [provision-templates-and-campaigns.md](provision-templates-and-campaigns.md) — how you get the
  `campaignId` you start journeys from.
- [resolve-actionable-step.md](resolve-actionable-step.md) — picking a target step when you don't
  have a running journey's submittable flag to rely on (e.g. a shared/partner campaign).
- [step-config-notifications-webhooks.md](step-config-notifications-webhooks.md) — a
  notification/webhook that fires when a step completes.
- Async trigger-and-poll (submit, then poll a `customData` sentinel) →
  [async-trigger-and-poll.md](async-trigger-and-poll.md).
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md), [api/README.md](../api/README.md).
