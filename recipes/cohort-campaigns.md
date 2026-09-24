# Launch a campaign from a cohort and keep it in sync

**Use when:** you want to act on a cohort's members, for example outreach or closing care gaps, by
running a workflow for each member. It also covers keeping that campaign aligned as the cohort's
membership changes.

**Routes:**
- launch: `POST /api/v2/cohort-definition/{id}/launch-campaign` → [agents.md](https://agents.1health.io/public/prod/api/v2/cohort-definition/_id_/launch-campaign/agents.md)
- vendor coverage: `POST …/{id}/campaign-coverage` → [agents.md](https://agents.1health.io/public/prod/api/v2/cohort-definition/_id_/campaign-coverage/agents.md)
- launched campaign details: `GET …/{id}/workflow-campaign` → [agents.md](https://agents.1health.io/public/prod/api/v2/cohort-definition/_id_/workflow-campaign/agents.md)
- membership sync: `GET` and `POST …/{id}/workflow-campaign/{workflowCampaignId}/member-coverage` → [agents.md](https://agents.1health.io/public/prod/api/v2/cohort-definition/_id_/workflow-campaign/_workflowCampaignId_/member-coverage/agents.md)
- workflow picker: `POST /api/v3/health/grid/workflow-template-group` → [agents.md](https://agents.1health.io/public/prod/api/v3/health/grid/workflow-template-group/agents.md)
- vendor, service, and measure pickers: `POST /api/graphql` → [agents.md](https://agents.1health.io/public/prod/api/graphql/agents.md)

**Reference code:** none public. See the Minimal example.

**Seen in:** 1health platform usage. The shapes come from the published docs and 1health's own
command center. Only the "no campaign yet" placeholder was verified on demo:
- launching wasn't exercised, because it enrolls real members, demo included;
- `campaign-coverage` wasn't exercised, because it needs a vendor and the demo QA org has none.

## Pattern

1. **An Active cohort launches one campaign.** The definition links to it through
   `CohortDefinitionInitiatesWorkflowCampaign`. The campaign's own detail carries
   `cohortDefinition: { id, name }`, so either side can find the other. Show the launch form only
   when the cohort has no linked campaign; otherwise show the campaign. Before any launch,
   `GET …/{id}/workflow-campaign` still returns `200`, with a placeholder object (`id: -1`,
   `"n/a"` fields, a 1970 `createdOn`), not a 404. Treat `id <= 0` as "no campaign"
   (verified on demo).
2. **Pick a patient workflow.** Offer published campaign-type template groups. Call
   `POST /api/v3/health/grid/workflow-template-group` with these `filterBy` entries:
   - `{ key: "type", operator: "contains", value: "Campaign" }`
   - `{ key: "publishedWorkflowTemplateId", operator: "notBlank" }`
   - optionally `{ key: "name", operator: "contains", value: search }`

   This is the patient case: each member becomes the patient of one journey. For processes that
   aren't about a patient, see [workflows-without-a-patient.md](workflows-without-a-patient.md).
3. **Optionally assign a vendor, the partner who works the campaign.** The pickers cascade through
   GraphQL, each supporting `searchText` and nested paging:
   - **vendor:** the orgs your org is a client of (`OrganizationIsAClientOfOrganization`);
   - **service:** that vendor's services (`OrganizationProvidesVendorService`);
   - **measures:** one or more quality measures that service covers
     (`VendorServiceProvidesVendorCoverage` → `VendorCoverageHasPrimaryQualityMeasure`).

   If you send `vendor`, all three of its fields are required:
   `{ id, serviceId, qualityMeasureIds }`.
4. **Preview the vendor's reach before launching.** Call
   `POST …/campaign-coverage { vendor: { id, serviceId, qualityMeasureIds } }`. It returns
   `{ coveredPatients }`: the cohort members inside the vendor's coverage area, which is defined by
   state and ZIP code. Re-check it about 500 ms after the selections stop changing, and show it as
   a share of the cohort's member count.
5. **Launch.** Call `POST …/launch-campaign?batchSize=` with
   `{ name, description, workflowTemplateGroupId, vendor? }`. `name` must be 1–256 characters and
   `description` 1–5000. It returns `{ id, name, message }`.
   - `batchSize` is the journey-creation chunk. It defaults to 2 and has the same trade-off as a
     campaign run: higher is faster, lower is more stable.
   - Journeys are created asynchronously, and the campaign moves from Initializing to In Progress.
6. **Show the launched campaign.** Call `GET …/{id}/workflow-campaign`, which returns
   `{ id, name, description, status, createdOn, createdBy, workflowTemplateGroup, assignedPartner, targetMembers, memberCount, openCareGaps, targetedOpenCareGaps }`.
   `assignedPartner` carries the vendor with its `service` and `qualityMeasures`.
7. **Keep the campaign in sync with the cohort.** As new snapshots change membership, call
   `GET …/workflow-campaign/{campaignId}/member-coverage`. It returns `{ additions, removals }`:
   - **additions** are cohort members who have no journey yet;
   - **removals** are journeys whose member has left the cohort.

   Apply them with `POST …/member-coverage?action=create-journeys` (adds the additions) or
   `?action=cancel-journeys` (cancels the removals). Before applying, confirm with the user: "Add
   12 members?" Afterwards, re-read the coverage.
   - Offer `create-journeys` only while the campaign is **In Progress**.
   - Offer neither action while it's **Updating**, because a change is already running.

## Primary vs fallback

- **Primary: a cohort-driven audience.** Use this when the target population can be expressed
  with the filter catalog. Membership follows the data, and you reconcile it with `member-coverage`.
- **Fallback: a label-tag audience.** Use this when the audience is a hand-picked list the catalog
  can't express. You tag records and run an ordinary campaign
  ([campaign-lifecycle-and-audience.md](campaign-lifecycle-and-audience.md)).
- **Never mix them.** Don't hand-create journeys inside a cohort campaign. A journey you start
  manually for someone the cohort doesn't include counts as a **removal**; 1health's campaign screen
  warns about exactly this. To change who's in, change the cohort (a new definition) or use a
  separate campaign.

## Minimal example

```ts
import { callApi } from "@/lib/api"

type Vendor = { id: number; serviceId: number; qualityMeasureIds: number[] } // all-or-nothing

export async function vendorReach(cohortId: number, vendor: Vendor) {
  const res = await callApi<{ coveredPatients: number }>("cohort/coverage", `/api/v2/cohort-definition/${cohortId}/campaign-coverage`, {
    method: "POST",
    body: JSON.stringify({ vendor }),
  })
  return res.data?.coveredPatients ?? 0
}

export async function launchFromCohort(cohortId: number, name: string, description: string, workflowTemplateGroupId: number, vendor?: Vendor) {
  return callApi<{ id: number; message: string }>("cohort/launch", `/api/v2/cohort-definition/${cohortId}/launch-campaign?batchSize=10`, {
    method: "POST",
    body: JSON.stringify({ name, description, workflowTemplateGroupId, ...(vendor ? { vendor } : {}) }),
  })
}

// Reconcile after membership changes. Always confirm with the user before applying.
export async function pendingChanges(cohortId: number, campaignId: number) {
  const res = await callApi<{ additions: number; removals: number }>(
    "cohort/member-coverage", `/api/v2/cohort-definition/${cohortId}/workflow-campaign/${campaignId}/member-coverage`,
  )
  return res.data ?? { additions: 0, removals: 0 }
}

export async function applyChanges(cohortId: number, campaignId: number, action: "create-journeys" | "cancel-journeys") {
  return callApi("cohort/member-coverage-apply", `/api/v2/cohort-definition/${cohortId}/workflow-campaign/${campaignId}/member-coverage?action=${action}`, {
    method: "POST",
    body: "{}",
  })
}
```

## Gotchas

- **Launching enrolls real members, on demo too.** Test with a deliberately narrow cohort.
- **`vendor` is all-or-nothing.** If you send it at all, `id`, `serviceId`, and a non-empty
  `qualityMeasureIds` are all required.
- **The `action` values are exact:** `create-journeys` and `cancel-journeys`.
- **`member-coverage` returns counts, not lists.** There's no route that names which members are
  additions or removals.
- **Campaign status strings:** `Prepared`, `Initializing`, `In Progress`, `Updating`,
  `Finished`, `Interrupted`, and `Canceled`. `Canceled` has one L (verified on demo); compare
  exact strings.
- **The targeted figures depend on the measures.** `targetMembers` and `targetedOpenCareGaps`
  reflect the quality measures the campaign targets, and 1health's form describes those measures
  as feeding the cohort's "Targeted Open Care Gaps".
- **Pick a sensible `batchSize` and keep it.** Journey creation is chunked, so a very large chunk
  trades stability for speed.

## Related

- [cohort-definitions.md](cohort-definitions.md) — the lifecycle; a cohort must be Active first.
- [cohort-snapshots-and-history.md](cohort-snapshots-and-history.md) — the snapshots that drive additions and removals.
- [campaign-lifecycle-and-audience.md](campaign-lifecycle-and-audience.md) — the campaign state machine and the tag-audience alternative.
- [partnership-relationship-types.md](partnership-relationship-types.md) — the client/vendor partnership the vendor picker reads.
- [workflows-journeys-steps.md](workflows-journeys-steps.md) — working the journeys the campaign creates.
