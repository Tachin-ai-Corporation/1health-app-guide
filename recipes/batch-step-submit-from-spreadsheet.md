# Submit one step across a whole campaign from an uploaded spreadsheet

**Use when:** you need to submit the same step across every journey in a campaign at once — e.g. an
ops user bulk-completing a step for hundreds of journeys from a file — instead of looping a
per-journey submit yourself. **Requires campaign-owner privileges.**
**Routes:** `PUT /api/v2/health/workflow-campaign/{id}/step/{wfStepId}/batch/submit` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-campaign/_id_/step/_wfStepId_/batch/submit/agents.md)
**Reference code:** none public — see the Minimal example.
**Seen in:** 1health platform usage

## Pattern

1. **Only specific step types support this path** — it isn't universal. Confirm the target step
   type is eligible (test against demo) before building upload UI for it; don't let a user pick any
   step and fail server-side.
2. **The request is one multipart file field, nothing else.** An XLSX spreadsheet with a header row
   matching the step's expected field names — there's no per-journey id list in the body; the
   server matches spreadsheet rows to journeys under the campaign itself.
3. **The response is a batch-job id, not a completion receipt.** A successful call means the file
   was accepted and enqueued, not that every row succeeded. There's no documented status-polling
   endpoint for that job id — treat this as fire-and-forget, and verify results afterward by
   re-reading the affected journeys' step states (or the campaign dashboard) rather than trusting
   the response alone.
4. **Campaign-owner privileges are required** — a caller without them should expect a rejection,
   not a partial success.

## Minimal example

```ts
import { authFetch, getOneHealthBaseUrl } from "@/lib/auth-client"

async function batchSubmitStepFromFile(campaignId: number, wfStepId: number, file: File): Promise<number> {
  const baseUrl = getOneHealthBaseUrl()
  const form = new FormData()
  form.append("file", file)   // .xlsx, header row must match the step's expected field names

  const res = await authFetch(
    `${baseUrl}/api/v2/health/workflow-campaign/${campaignId}/step/${wfStepId}/batch/submit`,
    { method: "PUT", body: form },
  )
  if (!res.ok) throw new Error("Batch submit rejected — check campaign-owner privileges and step eligibility")

  return res.json()   // a batch-job id: confirms enqueue only, not per-row success
}
```

## Gotchas

- **A successful response means "enqueued," not "every row applied"** — spot-check or re-read
  affected journeys afterward instead of trusting the 200.
- **Not every step type is eligible for this path** — verify per step type before offering it, or
  the call fails for a step a user was allowed to pick.
- **Header names must match the step's expected field names** — a mismatched header most likely
  fails individual rows rather than the whole upload; don't assume a rejected row surfaces loudly.

## Related

- [workflows-journeys-steps.md](workflows-journeys-steps.md) — the single-journey step-submit
  recipes this endpoint replaces for a whole-campaign fan-out.
- [campaign-lifecycle-and-audience.md](campaign-lifecycle-and-audience.md) — the campaign this batch
  submit is scoped to.
- [dynamic-step-fields.md](dynamic-step-fields.md) — the field names a spreadsheet's header row
  needs to match.
