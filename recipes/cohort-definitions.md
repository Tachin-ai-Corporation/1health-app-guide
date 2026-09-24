# Build and run a cohort (the command center)

**Use when:** you're building population-health tooling, a "command center" where managers do three things:
- define a segment of members (patients) from care-gap, member, insurance and care-quality data;
- watch the segment change over time;
- act on it by launching a campaign.

This is the hub recipe; three companion recipes go deeper.

**Routes:**
- create and update a definition: `POST /api/v2/cohort-definition` and `PUT /api/v2/cohort-definition/{id}` → [agents.md](https://agents.1health.io/public/prod/api/v2/cohort-definition/agents.md);
- member count and open care gaps: `POST /api/v2/cohort-definition/evaluate/overview` → [agents.md](https://agents.1health.io/public/prod/api/v2/cohort-definition/evaluate/overview/agents.md);
- a 50-row sample: `POST /api/v2/cohort-definition/evaluate` → [agents.md](https://agents.1health.io/public/prod/api/v2/cohort-definition/evaluate/agents.md);
- activate: `PUT /api/v2/cohort-definition/{id}/activate` → [agents.md](https://agents.1health.io/public/prod/api/v2/cohort-definition/_id_/activate/agents.md);
- disable: `PUT /api/v2/cohort-definition/{id}/disable` → [agents.md](https://agents.1health.io/public/prod/api/v2/cohort-definition/_id_/disable/agents.md);
- list definitions: `POST /api/v3/health/grid/cohort-definition` → [agents.md](https://agents.1health.io/public/prod/api/v3/health/grid/cohort-definition/agents.md);
- the filter catalog: `GET /api/v2/health/order/data-definition/list` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/order/data-definition/list/agents.md);
- read one definition back: `POST /api/graphql` → [agents.md](https://agents.1health.io/public/prod/api/graphql/agents.md).

**Reference code:** none public; see the Minimal example.
**Seen in:** 1health platform usage (a manager-facing population-health feature). Verified end to end on demo with a throwaway cohort: create, update, activate, snapshots, refresh, disable, and re-activate.

## What a cohort is

A **cohort definition** is a saved, named query over the tenant's members:
- it combines **filter groups** with AND/OR;
- each group holds **conditions**;
- each condition points at a **filter definition** from a platform catalog (care gaps, demographics,
  location, insurance, care-quality evidence).

Once you activate it, the platform keeps its membership as **snapshots**. A cohort can also
**launch one campaign**, and that campaign's journeys are the cohort's members.

The graph (these types and relationship keys are what you read through GraphQL):

```
CohortDefinition { name, description, state, measurementYear }
  └ CohortDefinitionHasConditionFilterGroup → ConditionFilterGroup { name, order, logicalOperator }
      └ ConditionFilterGroupHasDataFilterCondition → DataFilterCondition { order, value, comparisonOperator }
          └ DataFilterConditionHasDataFilterDefinition → DataFilterDefinition   (the catalog entry)
  └ CohortDefinitionInitiatesWorkflowCampaign → the campaign it launched
```

**How the logic combines (verified on demo):** conditions inside a group are always AND-ed. A
group's `logicalOperator` says how that group joins the groups before it, so the first group's
operator has no effect. To express "A or B", put A and B in separate groups and set the second
group to `OR`.

## Who gets it

1health's own portal shows the command center only to a user who meets all three of these:
- has the **System Admin, Manager, or Employee** role;
- belongs to an organization whose type includes **Go To Market**;
- belongs to an organization whose capabilities include **"Command Center"**.

Your app reads the last two from `GET /api/v2/tenant` (`organization.type[]` and
`organization.capabilities[]`); mirror that gate. It's a product entitlement, not security: on demo
the cohort APIs answered a System Admin in an org without the capability. Authorization comes from
the user's token, as everywhere else.

## Pattern: the lifecycle

1. **Load the filter catalog once.** Call `GET /api/v2/health/order/data-definition/list?workflowType=Cohort Definition`.
   It drives the whole condition editor → [cohort-filter-conditions.md](cohort-filter-conditions.md).
2. **Build the definition client-side:**
   ```
   { name, description, measurementYear, filterGroups: [{ name, order, logicalOperator, conditions }] }
   ```
   Validate the way 1health's own builder does: a name of at most 256 characters; a required
   description of at most 5000; a measurement year between 2000 and 2100; at least one group; at
   least one condition in every group.
3. **Preview on demand, not on every keystroke.** When the user applies the filters, send
   `{ filterGroups }` to two calls:
   - `evaluate/overview` returns the counts, `{ memberTotalCount, openCareGaps }`;
   - `evaluate` returns a sample of up to 50 members.

   Neither call persists anything.
4. **Save a Draft** with `POST /api/v2/cohort-definition`, which returns `{ id, name, state: "Draft", message }`.
   Save later edits with `PUT /api/v2/cohort-definition/{id}` and the same full body. A PUT replaces
   the whole tree. Only Drafts are editable.
5. **Activate** with `PUT …/{id}/activate`, which returns `200` with an empty body. The state goes
   straight to **Initializing** while the platform builds the first snapshot, then to **Active**.
   On demo a 155-member cohort had its first snapshot within seconds and reached Active in about
   34 s; larger populations take longer. Poll the state, or offer a refresh as 1health's builder
   does. History and campaign features wait until the cohort is Active.
6. **Read an Active cohort from its latest snapshot** instead of re-evaluating it. While the first
   snapshot is still empty, fall back to `evaluate`
   → [cohort-snapshots-and-history.md](cohort-snapshots-and-history.md).
7. **Act on the cohort:** launch one campaign from it, then keep the campaign in step as membership
   changes → [cohort-campaigns.md](cohort-campaigns.md).
8. **Retire it** with `PUT …/{id}/disable`, which returns `200` with an empty body. A Disabled
   cohort and its snapshots stay readable. 1health's builder offers no way back, but the API has
   one: `PUT …/activate` on a Disabled cohort returns `200` and runs it through Initializing again
   (verified). Decide deliberately whether your app offers re-activation.

| State | Edit (PUT) | Activate | Disable | Refresh | Snapshots & campaign |
|---|---|---|---|---|---|
| Draft | ✅ | ✅ | — | — | — |
| Initializing | — | — | — | — | wait (building) |
| Active | ❌ `400` | — | ✅ | ✅ | ✅ |
| Disabled | — | ✅ (API only) | — | ❌ `400` | read-only |

## Primary vs fallback

- **Counting.** For a Draft (or unsaved filters) the primary is `evaluate/overview`. For an Active
  cohort, read `snapshot/latest/overview`, and fall back to `evaluate/overview` only while no
  snapshot exists yet. Never count with `evaluate`: it returns at most 50 rows, and its page
  envelope reports `totalElements: 50` whatever the real size.
- **Reading one definition's tree.** The primary is **GraphQL** `CohortDefinition(filter: { id: { equal: … } })`
  with the nested group → condition → definition relations. There's no REST read of a definition.
  How to decode what comes back is in [cohort-filter-conditions.md](cohort-filter-conditions.md).
- **Listing definitions.** The primary is **the grid**, `POST /api/v3/health/grid/cohort-definition?page=&size=`
  with `{}` or `{ filterBy, orderBy }`; for example `{ key: "id", operator: "equals", value }`
  finds one row. Row keys (verified on demo): `id, name, description, state, membersTotalCount,
  careGapsTotalCount, campaign, created, updated`, plus the creator as `createdByPersonId`,
  `createdByPersonName`, `createdByPersonFirstName`, `createdByPersonLastName`, `createdByPersonEmail`,
  `createdByPersonPhoneNumber`, `createdByPersonPhoneNumberRegion`, and `createdByPersonUserId`. A
  Draft shows `-1` for both totals. Fall back to GraphQL only for fields the grid doesn't carry.

## Minimal example

```ts
import { callApi } from "@/lib/api"

type Condition = { definitionId: number; comparisonOperator: string; order: number; value: unknown }
type FilterGroup = { name: string; order: number; logicalOperator: "AND" | "OR"; conditions: Condition[] }
type CohortDefinitionBody = { name: string; description: string; measurementYear: number; filterGroups: FilterGroup[] }

// Preview the current filters: real counts plus a small sample. Nothing is persisted.
export async function previewCohort(filterGroups: FilterGroup[]) {
  const body = JSON.stringify({ filterGroups })
  const [overview, sample] = await Promise.all([
    callApi<{ memberTotalCount: number; openCareGaps: number }>("cohort/overview", "/api/v2/cohort-definition/evaluate/overview", { method: "POST", body }),
    callApi<{ data: { id: number; firstName: string; lastName: string; birthDate: string }[] }>("cohort/evaluate", "/api/v2/cohort-definition/evaluate", { method: "POST", body }),
  ])
  return { counts: overview.data, sample: sample.data?.data ?? [] } // the sample is capped at 50 rows
}

// Save a Draft, then activate it. The state becomes Initializing; poll until it's Active.
export async function saveAndActivate(definition: CohortDefinitionBody) {
  const created = await callApi<{ id: number; state: string }>("cohort/create", "/api/v2/cohort-definition", {
    method: "POST",
    body: JSON.stringify(definition),
  })
  if (!created.success) throw new Error(created.error)
  await callApi("cohort/activate", `/api/v2/cohort-definition/${created.data!.id}/activate`, { method: "PUT", body: "{}" })
  return created.data!.id
}
```

## Gotchas

- **`evaluate` is a capped sample, not a page.** It ignores `page` and `size`, returns 50 rows, and
  labels them `totalElements: 50, lastPage: true` even for a 300,000-member cohort (verified on
  demo). Get counts from `evaluate/overview`.
- **Send `{ filterGroups }` to evaluate.** 1health's builder also sends name, description, and
  `measurementYear`, but on demo those fields changed nothing. An empty `filterGroups` is a `400`
  ("Request DTO is null").
- **The definition's `measurementYear` doesn't filter the preview.** To scope care gaps to a year,
  add the catalog's *Measurement Year* condition. What the stored year drives after activation
  isn't documented, so set it to the year you're working in.
- **Operators are exact strings from the catalog, and they're case-sensitive.** `"Is Any Of These"`
  works; `"is any of these"` is a `400` "Invalid comparison operator", and so is the grid's
  `greaterThan` dialect.
- **The API enforces the lock, not just the UI.** A `PUT` on an Active definition returns `400`
  "The Cohort Definition is in {Active} state and it can not be updated." (verified). To change the
  logic of an Active cohort, create a new Draft that copies its groups.
- **A save replaces the whole tree.** Every `PUT` creates new group and condition records, with new
  ids, so never keep a group or condition id across saves. Rebuild the tree from the latest
  read-back instead.
- **The grid row includes the creator's email and phone number.** Show the name at most, and keep
  the rest out of the UI and the logs.
- **Unset totals are `-1`.** A Draft's `membersTotalCount` and `careGapsTotalCount` come back as `-1`,
  so render them as "—", not as a count.
- **Activation is asynchronous.** Initializing can take a while on a large population, so don't
  block the UI on it.
- **Demo may have members but no care-gap data.** A broad filter on demo matched about 319,000
  members with 0 open care gaps, so plan your QA data accordingly.
- **The entitlement gate isn't security** (see *Who gets it* above).

## Related

- [cohort-filter-conditions.md](cohort-filter-conditions.md) — the catalog, the operators, value encoding, read-back, and templates.
- [cohort-snapshots-and-history.md](cohort-snapshots-and-history.md) — Active cohorts: latest counts and members, history, and comparing snapshots.
- [cohort-campaigns.md](cohort-campaigns.md) — launching a campaign from a cohort and keeping it in sync.
- [campaign-lifecycle-and-audience.md](campaign-lifecycle-and-audience.md) — a cohort versus a label-tag audience.
- [graphql-read-path.md](graphql-read-path.md) · [grid-list-views.md](grid-list-views.md) · [schema-discovery.md](schema-discovery.md)
- [decision-steps.md](decision-steps.md) — workflow decision branches store their conditions as the same `DataFilterCondition` records.
