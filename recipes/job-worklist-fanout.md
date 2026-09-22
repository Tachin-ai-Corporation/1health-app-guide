# Job worklist fan-out

> **Advanced / guardrailed pattern.**

**Use when:** many journeys can each have a long-running external job in flight (document
extraction, AI analysis) and you need a session-wide way to advance whichever ones are running and
list status for a worklist UI — without one page polling N journeys forever, and without a
per-page poller being the only thing that can ever finish a job.
**Routes:** n/a — aggregates `POST /api/v2/query` (bulk index read) →
[agents.md](https://agents.1health.io/public/prod/api/v2/query/agents.md) + `GET /api/v2/journey/{id}/steps`
(bounded fan-out) → [agents.md](https://agents.1health.io/public/prod/api/v2/journey/_id_/steps/agents.md)
+ your own async-job status/result endpoints (not 1health).
**Reference code:** [`jobs.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/lib/expertdx/jobs.ts#L81) ·
[`jobs/poll/route.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/app/api/expertdx/jobs/poll/route.ts#L44)
**Seen in:** expertdx (case extraction + AI diagnostics queue)

## Pattern

1. **Denormalize each job's status** ("running"/"done"/"error") onto the owning journey's
   `customData` index — one bulk `/query` over the campaign then reveals the in-flight set without
   reading every journey's steps.
2. **One shared "advance" function per job kind harvests it** — checks upstream status, and on
   settle, writes the result onto the step and promotes the terminal state onto the index. Call
   this SAME function from a page poll, a GET route, and a session-wide background poller, so a
   job finishes even after its tab navigates away.
3. **Make harvesting idempotent** — a `harvested` flag stops a second poll from re-reading a
   possibly-expired upstream result.
4. **Bound the fan-out**: cap in-flight jobs advanced per poll, and bound per-journey detail reads
   with a small worker pool — never one socket per row.

## Minimal example

```ts
const MAX_ADVANCE = 8

async function advanceInFlightJobs(campaignId: number) {
  const rows = await runQueryRows({
    key: "WorkflowTemplate",
    attributes: ["id", "customData"],
    filter: eq("workflowCampaignId", campaignId),
  })
  const inFlight = rows
    .filter((r) => parseCustomData(findAttr(r, "customData"))?.jobIndex?.status === "running")
    .slice(0, MAX_ADVANCE)

  for (const row of inFlight) await advanceJob(findAttr<number>(row, "id")!)  // the one shared harvester
}
```

## Gotchas

- **Harvest logic living only inside the page that started the job** means it never finishes if
  the user navigates away — lift it into a shared function every poller calls.
- **An un-flagged re-harvest can re-read a result after the vendor deletes it** — persist on settle
  and mark the job harvested.
- **`id =in= (...)` can 400 on a numeric attribute** on some types — prefer an OR-of-equals filter.

## Related

- [async-trigger-and-poll.md](async-trigger-and-poll.md) (D7) — the single-journey version.
- [external-job-pipeline.md](external-job-pipeline.md) (I4) — the submit/poll contract fanned out over.
- [batched-enrichment.md](batched-enrichment.md) (B7) — the `id=in=()` gotcha in a read-only context.
