# Journey orchestration

**Use when:** one user action must create a journey and drive it through a fixed sequence of
steps in one go — some steps required, some best-effort — with partial failure that leaves a
usable (not corrupted) journey behind, and a way to retire one that was abandoned or wrong.
**Routes:** `POST /api/v2/journey` (create) →
[agents.md](https://agents.1health.io/public/prod/api/v2/journey/agents.md) · step submits →
[agents.md](https://agents.1health.io/public/prod/api/v2/journey/_id_/step/_stepId_/submit/agents.md)
· `POST /api/v2/data/custom-data/bulk` (persist derived facts) →
[agents.md](https://agents.1health.io/public/prod/api/v2/data/custom-data/bulk/agents.md) ·
`PUT /api/v2/journey/uat` (retire) → [agents.md](https://agents.1health.io/public/prod/api/v2/journey/uat/agents.md)
**Reference code:** [`journey.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/api/journey.ts#L933) (`createDischargeJourney`, `setJourneyUat` at [L105](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/api/journey.ts#L105))
**Seen in:** pcp-tcm (discharge intake orchestration)

## Pattern

1. **Create the journey bare**, or adopt one that already exists (e.g. handed off from another
   surface) — don't block creation on having every fact in hand yet.
2. **Persist derived/pre-computed facts immediately**, before any fallible step runs. A value like
   an anchor date or a source-record link must survive even if a later step fails, and some of
   these facts become WRONG if re-derived later (e.g. "days since admission" computed tomorrow
   instead of today). Read-modify-write into `customData` rather than a bare overwrite — the
   journey may already carry sibling data if it was adopted.
3. **Fetch the step list once**, then walk a fixed, named sequence — resolve each step by name and
   submit it if you have the data for it.
4. **Classify each step as REQUIRED or BEST-EFFORT.** A required step's failure aborts the whole
   orchestration and returns a clear error; a best-effort step's failure is logged/warned and the
   flow continues (most attachments and derived-record writes are best-effort; identity/ownership
   steps are usually required).
5. **Report progress via a callback** (`{ step, status }`) after each phase — a multi-call sequence
   without incremental feedback looks hung even when it's working.
6. **Warn loudly, never fail silently, when a named step isn't found** — log the full list of
   available step names so a template rename is caught immediately instead of quietly skipping a
   whole phase.
7. **Retire, don't delete**, an abandoned or erroneous journey — flip the UAT flag so it drops out
   of real cohort counts and dashboards while the record survives for audit.

## Minimal example

```ts
import { createJourney, fetchJourneySteps, findStepByName, submitStep, mergeCustomData } from "@/lib/api"

export interface OrchestrationInput {
  campaignId: number
  subjectId: number
  anchorDate: string
  existingJourneyId?: number   // adopt a journey created elsewhere instead of making a new one
}

export async function orchestrateJourney(
  input: OrchestrationInput,
  onProgress?: (step: string, status: "in-progress" | "complete" | "error" | "warning") => void,
) {
  onProgress?.("create", "in-progress")
  const journeyId =
    input.existingJourneyId ?? (await createJourney(input.campaignId)).data?.id
  if (!journeyId) return { success: false, error: "Failed to create journey" }
  onProgress?.("create", "complete")

  // Persist the derived fact BEFORE any step that could fail — read-modify-write survives
  // a journey that was adopted (and may already carry sibling customData).
  await mergeCustomData("WorkflowTemplate", journeyId, { anchorDate: input.anchorDate })

  const steps = (await fetchJourneySteps(journeyId)).data
  const identityStep = findStepByName(steps, "Identify Subject")
  if (!identityStep) {
    onProgress?.("identify", "warning")   // REQUIRED step missing — still surfaces as an error below
  } else {
    const res = await submitStep(journeyId, identityStep.id, { subjectId: input.subjectId })
    if (!res.success) {
      onProgress?.("identify", "error")
      return { success: false, error: res.error, journeyId }   // required: abort here
    }
    onProgress?.("identify", "complete")
  }

  const noteStep = findStepByName(steps, "Add Note")
  if (noteStep) {
    const res = await submitStep(journeyId, noteStep.id, { note: "Created by orchestration" })
    onProgress?.("note", res.success ? "complete" : "warning")   // best-effort: never aborts
  }

  return { success: true, journeyId }
}
```

## Gotchas

- **A required step's error must name the step AND the payload you sent.** Two different steps can
  both reject with the platform's same generic "Organization with id: N not found" — indistinguishable
  without echoing what you sent alongside the step name.
- **"Retire" is a status flag, not a delete.** Any dashboard/query over this campaign must already
  exclude UAT journeys, or a retired one keeps counting.
- **A missing named step usually means a template rename**, not a bug in your code — the warning
  log's list of available step names is what makes that diagnosable in minutes instead of hours.
- **Progress callbacks are for UI feedback only** — a caller that ignores `onProgress` must still
  get a correct final success/failure result; don't fold control flow into the callback.
- **Best-effort failures must still be visible somewhere** (a warning toast, a log line) — silent
  best-effort failure is how "the attachment never got there" goes unnoticed for weeks.

## Related

- [async-trigger-and-poll.md](async-trigger-and-poll.md) (D7) — when one of your steps kicks off
  an async backend job instead of completing synchronously.
- [workflows-journeys-steps.md](workflows-journeys-steps.md) (D1) — the single-step-submit
  foundation this builds on.
- [write-safety-and-fail-closed.md](write-safety-and-fail-closed.md) (C3) — the read-modify-write
  discipline behind step 2.
- [audit-trail-in-custom-data.md](audit-trail-in-custom-data.md) (C5)
- [read-write-custom-data.md](read-write-custom-data.md) — the `mergeCustomData` call in step 2.
