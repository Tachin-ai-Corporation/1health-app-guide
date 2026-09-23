# Run a campaign through its lifecycle, and define who it targets

**Use when:** you're building admin/ops tooling that runs a campaign end-to-end — not just
creating and activating one (see [provision-templates-and-campaigns.md](provision-templates-and-campaigns.md))
but knowing what states it can be in, recovering from an interrupted bulk run, checking who it
will actually enroll before running it, and keeping its dashboard tiles current.
**Routes:** `POST/PUT /api/v2/health/workflow-campaign` (create/update, incl. `labelTagIds`) → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-campaign/agents.md) · `POST .../{id}/run` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-campaign/_id_/run/agents.md) · `PUT .../{id}/cancel` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-campaign/_id_/cancel/agents.md) · `PUT .../{id}/finish` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-campaign/_id_/finish/agents.md) · `POST .../{id}/restart` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-campaign/_id_/restart/agents.md) · `PUT .../{id}/use-latest-template` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-campaign/_id_/use-latest-template/agents.md) · `GET .../{id}/tagged-instance-count` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-campaign/_id_/tagged-instance-count/agents.md)
**Reference code:** [`lib/api/campaign.ts`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/lib/api/campaign.ts) (`createCampaign` already takes the audience tags; `activateCampaign` is the sibling call this recipe's other transitions extend the same way)
**Seen in:** 1health platform usage — extends the campaign object already used in template,
secure-share, pcp-tcm (see [provision-templates-and-campaigns.md](provision-templates-and-campaigns.md))

## Pattern

1. **Know the state machine.** A campaign moves Prepared → Initializing → In Progress → Finished,
   with Cancelled and Interrupted reachable as side-exits from the active states. Don't model it as
   a bare "created vs activated" boolean.
2. **Define the audience declaratively, not as an id list.** A campaign is created with a set of
   label-tag ids (`labelTagIds`) — any record tagged with one of those tags is in scope. Tagging
   (or untagging) records is a separate, ordinary bulk operation you can do any time, before or
   after the campaign exists (see [bulk-tagging.md](bulk-tagging.md)). A campaign can instead
   target a saved, dynamic query — see [cohort-definitions.md](cohort-definitions.md) — rather than
   a fixed tag set; the two are alternative audience mechanisms, not layers of one system. **An
   audience is optional.** A campaign whose journeys your app starts on demand (one per file or
   per export) needs none, and no patient has to be involved at all; see
   [workflows-without-a-patient.md](workflows-without-a-patient.md).
3. **Check the population before running.** `tagged-instance-count` answers "how many records
   match right now" without running anything — use it to warn before enrolling zero, or an
   unexpectedly large, population. It's a live snapshot: a record tagged/untagged between the check
   and the actual run can still change what gets enrolled.
4. **Run, tuning batch size if needed.** `run` accepts a `batchSize` query param (how many journeys
   to create per chunk — lower is more stable, higher is faster) and kicks off bulk enrollment.
5. **Treat Interrupted as resumable, not failed.** If the bulk run dies partway (e.g. a server
   redeploy mid-run), the campaign lands in Interrupted. Recover with `restart` (same `batchSize`
   param) — don't ask the user to start over, and don't build your own from-scratch retry.
6. **Cancel and finish are explicit, terminal transitions.** `cancel` requires a
   `cancellationReason` (1–5000 chars) in the body; neither transition is reachable again once a
   campaign lands on it.
7. **Re-point at the latest template without recreating the campaign.** `use-latest-template`
   updates which template a campaign's *future* journeys clone from — it does not retroactively
   change journeys already in flight.
8. **Refresh dashboard tiles only when you suspect they're stale**, and know the display config
   itself is admin-writable — see [campaign-dashboard-aggregation.md](campaign-dashboard-aggregation.md)
   for the read/refresh split and the tile-editing caveats.

## Minimal example

```ts
import { authFetch, getOneHealthBaseUrl } from "@/lib/auth-client"

const baseUrl = getOneHealthBaseUrl()

// Pre-flight: how many records currently match the campaign's audience?
const countRes = await authFetch(`${baseUrl}/api/v2/health/workflow-campaign/${campaignId}/tagged-instance-count`)
const matched: number = await countRes.json()
if (matched === 0) confirmBeforeRunningAnEmptyCampaign()

// Run — batchSize tunes journeys-created-per-chunk (default 2; higher = faster, less stable).
await authFetch(`${baseUrl}/api/v2/health/workflow-campaign/${campaignId}/run?batchSize=5`, { method: "POST" })

// ...if that run gets interrupted (e.g. a deploy), resume it — don't re-run from scratch.
await authFetch(`${baseUrl}/api/v2/health/workflow-campaign/${campaignId}/restart?batchSize=5`, { method: "POST" })

// Cancel is a reasoned transition, not a bare POST.
await authFetch(`${baseUrl}/api/v2/health/workflow-campaign/${campaignId}/cancel`, {
  method: "PUT",
  body: JSON.stringify({ cancellationReason: "Superseded by a corrected campaign" }),
})

// Adopt whatever is currently published — affects new journeys only.
await authFetch(`${baseUrl}/api/v2/health/workflow-campaign/${campaignId}/use-latest-template`, { method: "PUT" })
```

## Gotchas

- **Interrupted has a dedicated recovery action** — treat it as "resumable," never as a terminal
  failure that requires abandoning the campaign.
- **Running against zero matching records is allowed, not blocked** — worth a client-side
  confirmation prompt, not a hard stop.
- **`use-latest-template` never touches journeys already in flight** — only what's created after
  the call clones from the newly-adopted template.
- **`cancel` requires a reason string in the body** — a bare `PUT` with no body is rejected.
- **The audience count is a snapshot, not a lock** — tagging is live, so the population that
  actually gets enrolled when you `run` can differ from what you counted moments earlier.
- **A campaign with no audience always counts zero here.** `tagged-instance-count` measures the
  audience, not the journeys your app started itself, so count those journeys instead (the
  journeys grid, filtered by `workflowCampaignId`).

## Related

- [provision-templates-and-campaigns.md](provision-templates-and-campaigns.md) — creating and
  first-activating the campaign this recipe then runs through its lifecycle.
- [template-versions-draft-publish.md](template-versions-draft-publish.md) — the template version
  `use-latest-template` re-points a campaign at.
- [cohort-definitions.md](cohort-definitions.md) — the dynamic-query alternative to a fixed
  label-tag audience.
- [bulk-tagging.md](bulk-tagging.md) — tagging/untagging the records a tag-based audience matches.
- [workflows-without-a-patient.md](workflows-without-a-patient.md) — a campaign with no audience at
  all, for a process that has no patient.
- [campaign-dashboard-aggregation.md](campaign-dashboard-aggregation.md) — reading KPIs and
  refreshing them once stale.
- [share-with-partner-org.md](share-with-partner-org.md) — sharing a running campaign with a
  partner organization.
