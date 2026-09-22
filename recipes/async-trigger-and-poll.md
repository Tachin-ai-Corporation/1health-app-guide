# Async trigger-and-poll

**Use when:** submitting a step kicks off a backend action that takes real time (a document
render, a notification send) and the platform gives you no webhook or callback for it — you must
fire the trigger, then find out you're done by polling.
**Routes:** `POST /api/v2/journey/{id}/step/{stepId}/submit?attachment` (the trigger) →
[agents.md](https://agents.1health.io/public/prod/api/v2/journey/_id_/step/_stepId_/submit/agents.md)
· poll via `POST /api/v2/query` (project `customData` only) →
[agents.md](https://agents.1health.io/public/prod/api/v2/query/agents.md)
**Reference code:** [`use-notification-actions.ts`](https://github.com/Tachin-ai-Corporation/v0-trc-care-coordinator/blob/main/components/task-components/shared/use-notification-actions.ts#L122)
**Seen in:** trc-care-coordinator (PDF notification generation)

## Pattern

1. **Resolve the action step and its trigger field** — fetch the journey's steps, find the named
   step by label, fetch its live field schema, and find the dynamic field that selects the action
   (e.g. a "Select Action" dropdown) by its label.
2. **Snapshot the sentinel BEFORE firing.** Read the cheap fields you'll watch for change (a status
   enum, a "last result" object) off the journey's `customData` and keep that snapshot in memory.
3. **Submit the step** with the trigger value. The response only confirms the submit was accepted —
   it carries no result. The backend action runs asynchronously after this call returns.
4. **Poll the cheap read**, not the full journey: re-read just `customData` on an interval and
   compare against the snapshot. Stop as soon as ANY watched field differs from its snapshot.
5. **Cap total attempts/time**, and resolve either way when the cap is hit — do one final refresh
   so the UI doesn't stay stuck on "generating" forever if the backend never flips the field.
6. **Clear the poll timer** on unmount, on success, and before starting a retry — a stale timer can
   fire against gone state or double-schedule a second poll loop.

## Minimal example

```ts
import { fetchJourneySteps, findStepByName, fetchStepInfo, submitStepFields, readCustomData } from "@/lib/api"

const ACTION_STEP_NAME = "Notification Actions"     // your named trigger step
const TRIGGER_FIELD_LABEL = "Select Action"         // the dynamic field that selects the action
const TRIGGER_VALUE = "Generate Notification PDF"   // the action to run
const SENTINEL_KEY = "processingStatus"             // the customData field that flips when done

/** Fire the async backend action, then poll a customData sentinel until it changes. */
export async function triggerAndPoll(
  journeyId: number,
  opts: { maxAttempts?: number; intervalMs?: number } = {},
): Promise<{ changed: boolean }> {
  const { maxAttempts = 6, intervalMs = 2000 } = opts

  const steps = await fetchJourneySteps(journeyId)
  const step = findStepByName(steps.data, ACTION_STEP_NAME)
  if (!step) throw new Error(`Step "${ACTION_STEP_NAME}" not found`)

  const info = await fetchStepInfo(journeyId, step.id)
  const fields = info.data?.configuration?.metadata?.dynamicFields?.custom?.fields ?? []
  const trigger = fields.find((f) => f.label === TRIGGER_FIELD_LABEL)
  if (!trigger) throw new Error(`Field "${TRIGGER_FIELD_LABEL}" not found`)

  const before = await readCustomData("WorkflowTemplate", journeyId)
  const beforeSnapshot = JSON.stringify(before[SENTINEL_KEY] ?? null)

  await submitStepFields(journeyId, step.id, fields, { [trigger.fieldIdentifier]: TRIGGER_VALUE })

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    await new Promise((resolve) => setTimeout(resolve, intervalMs))
    const after = await readCustomData("WorkflowTemplate", journeyId)
    if (JSON.stringify(after[SENTINEL_KEY] ?? null) !== beforeSnapshot) {
      return { changed: true }   // sentinel flipped — caller re-fetches the real UI state once
    }
  }
  return { changed: false }      // gave up — caller should still refresh once, just in case
}
```

## Gotchas

- **There is no webhook here** — the sentinel poll is the ONLY completion signal. Don't assume a
  push notification will ever arrive for this action.
- **Poll the cheap read.** Re-fetching the full steps tree (or the whole journey) on every tick
  multiplies load for no benefit; project just `customData`.
- **Compare a snapshot taken before the trigger**, not an absolute "is it done" value — some
  backends transit through and back to a resting status between polls, so watching one enum can
  miss a fast in-and-out transition. Watching the JSON-stringified value of more than one sentinel
  field is safer than watching a single flag.
- **Always cap attempts/time and always resolve** on timeout with one last refresh — an uncapped
  poll leaks timers and leaves the UI stuck if the backend never flips the field.
- **Don't reuse the trigger's error handling for the poll.** A transient failure reading the poll
  should retry quietly; a failure on the trigger submit should surface immediately.

## Related

- [journey-orchestration.md](journey-orchestration.md) (D8) — when the async action is one step
  inside a larger multi-step flow rather than the whole interaction.
- [job-worklist-fanout.md](job-worklist-fanout.md) (D10, Advanced) — the multi-journey,
  denormalized-index generalization of this same idea.
- [workflows-journeys-steps.md](workflows-journeys-steps.md) (D1) — the foundation this builds on.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md).
