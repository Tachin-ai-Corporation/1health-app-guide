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
   round trip. A campaign id is all a journey needs; it doesn't need a patient or a subject
   ([workflows-without-a-patient.md](workflows-without-a-patient.md)).
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
- **C — dynamic fields + a file**: same echo-all body, sent as indexed multipart parts —
  `rawData[0].data` is the JSON-stringified echoed metadata object, and each field carrying a NEW
  file gets its own subsequent slot (`rawData[n].file` + `rawData[n].data = { identifier }`),
  paired by index. Deleting a previously uploaded file (no new file chosen) reuses the identical
  endpoint with no `.file` part at all: `rawData[n].data = { identifier, name, id, delete: true }`.

## Primary vs fallback

- **Primary — the journey-id routes:** always resolve the running instance's own **journey id**
  (from a grid row, a resolved campaign, or wherever you found it) and use the generic
  `journey/{id}/...` family for reading/advancing steps and listing documents. This is documented,
  and confirmed to resolve correctly whether the journey was started from a campaign or from an
  order — an order's own id and its journey's id are two different numbers, and mixing them up
  doesn't necessarily fail loudly (both are plain numeric ids in the same space, so passing the
  wrong one can silently target the wrong instance rather than 404).
- **Fallback — the order-keyed aliases:** `GET /api/v2/health/order/{orderId}/journey`,
  `GET .../order/{orderId}/step/{stepId}/info`, `POST .../order/{orderId}/step/{stepId}/submit`,
  `GET .../order/{orderId}/documents` (not yet in the published docs) exist and work, but reach for
  them only if you genuinely hold just the order id and haven't resolved its `journeyId` yet —
  prefer resolving the journey id and switching to the primary family over depending on these
  long-term.

> **⚠ Not yet in 1health's published API docs:** `GET /api/v2/health/order/{orderId}/journey`,
> `GET .../order/{orderId}/step/{stepId}/info`, `POST .../order/{orderId}/step/{stepId}/submit`,
> `GET .../order/{orderId}/documents`. 1health supports these for third-party apps, but
> agents.1health.io has no page for them yet — the shapes shown here come from working apps. Test
> them against demo before you rely on them.

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
- **A journey's steps are a SINGLE/GROUP/DECISION tree at the source** — the flat array
  `fetchJourneySteps` gives you is already flattened for you. An unresolved DECISION branch means
  the true step count is genuinely unknown until a submit resolves which branch was taken; don't
  treat the current flattened length as final near a branch point. If you ever work from the raw
  tree instead of the flat endpoint, branching templates need their own traversal (inspect
  `key`/`metadata.nodeType`) — don't build UI that jumps to an arbitrary step.
- **A step can be resolved three ways**: by numeric id (`.../step/{stepId}/info`, once you have it
  from the flat steps list — the normal path), by key/name
  ([`GET .../step/{stepKey}`](https://agents.1health.io/public/prod/api/v2/journey/_id_/step/agents.md),
  when you don't have the id yet — but this returns a LIST, since a repeatable step can have
  multiple submissions; never assume `[0]`), or by reading the whole nested journey tree (rarely
  needed by a third-party app — see [resolve-actionable-step.md](resolve-actionable-step.md)).
- **Not every "journey-level bulk" endpoint shares one body shape.** Assign/unassign-users takes an
  ARRAY of one object even for a single id (`[{ journeyIds, userIds }]`) — but bulk status and the
  UAT toggle each take a single PLAIN OBJECT with array-valued fields instead:
  `PUT /journey/status/bulk` is `{ journeyIds, status }`; `PUT /journey/uat` is
  `{ idsToSet, idsToUnset }`. Check each endpoint's shape individually rather than assuming one
  convention generalizes.
- **Journey status has a small, explicit transition graph, not free movement.**
  `PUT /journey/status/bulk` only accepts three target values — `"In Progress"`, `"On Hold"`,
  `"Cancelled"` — and the platform rejects some transitions outright (e.g. you cannot move a
  completed journey back to "In Progress"). "Completed" and "Rejected" are terminal and reached
  other ways (a step completing normally, or — for an order-sourced journey — the order's own
  outcome transition), never by setting them through this endpoint.

## Related

- [dynamic-step-fields.md](dynamic-step-fields.md) — resolving a step's field ids before submit.
- [provision-templates-and-campaigns.md](provision-templates-and-campaigns.md) — how you get the
  `campaignId` you start journeys from.
- [workflows-without-a-patient.md](workflows-without-a-patient.md) — running a process that has no
  patient (no patient step, no audience, one journey per run).
- [campaign-lifecycle-and-audience.md](campaign-lifecycle-and-audience.md) — running, cancelling,
  and recovering the campaign these journeys are enrolled from.
- [decision-steps.md](decision-steps.md) — authoring the DECISION nodes that make a journey's step
  tree branch.
- [resolve-actionable-step.md](resolve-actionable-step.md) — picking a target step when you don't
  have a running journey's submittable flag to rely on (e.g. a shared/partner campaign).
- [step-config-notifications-webhooks.md](step-config-notifications-webhooks.md) — a
  notification/webhook that fires when a step completes.
- Async trigger-and-poll (submit, then poll a `customData` sentinel) →
  [async-trigger-and-poll.md](async-trigger-and-poll.md).
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md), [api/README.md](../api/README.md).
