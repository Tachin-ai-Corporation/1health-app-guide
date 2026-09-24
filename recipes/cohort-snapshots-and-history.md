# Read an active cohort: snapshots, history, and change over time

**Use when:** a cohort is **Active** and you need any of these:
- its current size and care-gap totals;
- a sample of its members;
- how it changed between snapshots.

**Routes:**
- `GET /api/v2/cohort-definition/{id}/snapshot/latest/overview` → [agents.md](https://agents.1health.io/public/prod/api/v2/cohort-definition/_id_/snapshot/latest/overview/agents.md)
- `GET …/snapshot/latest/members` → [agents.md](https://agents.1health.io/public/prod/api/v2/cohort-definition/_id_/snapshot/latest/members/agents.md)
- `GET …/snapshot/list` → [agents.md](https://agents.1health.io/public/prod/api/v2/cohort-definition/_id_/snapshot/list/agents.md)
- `PUT …/{id}/refresh` → [agents.md](https://agents.1health.io/public/prod/api/v2/cohort-definition/_id_/refresh/agents.md)
- `GET …/snapshot/{cohortSnapshotId}/export` → [agents.md](https://agents.1health.io/public/prod/api/v2/cohort-definition/_id_/snapshot/_cohortSnapshotId_/export/agents.md) (see the caveat below)

**Reference code:** none public — see the Minimal example.
**Seen in:** 1health platform usage. Shapes are from the published docs, cross-checked against how 1health's own command center reads them. Demo had no Active cohort to exercise these routes on, so confirm them on your first Active cohort.

## Pattern

1. **A snapshot is the platform's stored membership of an Active cohort at one point in time:**
   `{ id, created, status, errorMessage, memberCount, openCareGaps, targetedMembers, targetedOpenCareGaps }`.
   The platform makes them. The first is built while the definition is **Initializing**, right
   after activation.
2. **Get current numbers from the latest snapshot:** `snapshot/latest/overview`.
   - The `targeted*` fields count the members and care gaps covered by the campaign launched from
     the cohort, for the measures that campaign targets ([cohort-campaigns.md](cohort-campaigns.md)).
   - Show them only for Active cohorts, as 1health's command center does: two tickers for a Draft,
     four for an Active cohort.
   - While the first snapshot is still being built, the response has no `id`. Fall back to
     `evaluate/overview` with the definition's `filterGroups` until it has one.
3. **Get a member sample from the latest snapshot:** `snapshot/latest/members` returns a Page of up
   to 50 members, `{ id, firstName, lastName, birthDate, created, updated, externalSystems[{ name, externalSystemId }] }`.
   If it's empty (still building), fall back to `evaluate` with the same filters.
4. **Show history** from `snapshot/list?page=&size=&search=&status=`, which is paged (`page` 0,
   `size` 50 by default).
   - Ask for `status=Success` to list only usable snapshots. The product also shows
     `In Progress`, `Partial Success`, and `Failure`.
   - `errorMessage` says why a snapshot failed.
5. **Compare two points in time:** pick a snapshot and diff its four counts against the latest
   (latest minus selected). Show the deltas with a sign.
6. **Handle on-demand refresh cautiously.** `PUT …/{id}/refresh` is documented, but its effect isn't
   described, and 1health's own command center doesn't call it. Try it on a demo cohort before you
   offer a "refresh now" button.

## Primary vs fallback: "everyone in the cohort"

No endpoint returns the full member list page by page. `snapshot/latest/members` and `evaluate`
both stop at 50 rows.

- **Primary: act through a campaign.** To do something for every member, launch a campaign from
  the cohort. The campaign gets one journey per member, and you page those journeys with the
  journey grid filtered by `workflowCampaignId` → [cohort-campaigns.md](cohort-campaigns.md).
- **Fallback: the member export.** `snapshot/{cohortSnapshotId}/export?fileName=` is the only
  full-member file. It's an **async export job**: it returns a task id, and the file shows up later
  in the export log. Treat it like any async export
  ([anti-patterns](../setup/anti-patterns.md)). Offer it at most as a user-started "download" with
  honest progress and failure states, and never build app logic that waits on it.

## Minimal example

```ts
import { callApi } from "@/lib/api"

type Snapshot = {
  id?: number; created?: string; status?: string; errorMessage?: string
  memberCount?: number; openCareGaps?: number; targetedMembers?: number; targetedOpenCareGaps?: number
}
const count = (n?: number) => (typeof n === "number" && n >= 0 ? n : 0) // unset numbers arrive as -1

// Current numbers for an Active cohort. Use the snapshot; fall back to a live evaluation while it builds.
export async function currentCohortNumbers(cohortId: number, filterGroups: unknown[]) {
  const latest = await callApi<Snapshot>("cohort/latest", `/api/v2/cohort-definition/${cohortId}/snapshot/latest/overview`)
  const snap = latest.success ? latest.data : undefined
  if (snap?.id) {
    return {
      source: "snapshot" as const,
      members: count(snap.memberCount), openCareGaps: count(snap.openCareGaps),
      targetedMembers: count(snap.targetedMembers), targetedOpenCareGaps: count(snap.targetedOpenCareGaps),
    }
  }
  const live = await callApi<{ memberTotalCount: number; openCareGaps: number }>(
    "cohort/overview", "/api/v2/cohort-definition/evaluate/overview",
    { method: "POST", body: JSON.stringify({ filterGroups }) },
  )
  return { source: "live" as const, members: count(live.data?.memberTotalCount), openCareGaps: count(live.data?.openCareGaps) }
}

// History: successful snapshots, newest page first, each diffed against the latest.
export async function snapshotHistory(cohortId: number, latest: Snapshot, page = 0) {
  const res = await callApi<{ data: Snapshot[]; totalElements: number }>(
    "cohort/snapshots", `/api/v2/cohort-definition/${cohortId}/snapshot/list?page=${page}&size=20&status=Success`,
  )
  return (res.data?.data ?? []).map((s) => ({
    ...s,
    deltaMembers: count(latest.memberCount) - count(s.memberCount),
    deltaOpenCareGaps: count(latest.openCareGaps) - count(s.openCareGaps),
  }))
}
```

## Gotchas

- **`snapshot/latest/members` is capped at 50,** described in the docs as "the last 50 members".
  Paging it gets you nothing more.
- **Don't re-evaluate an Active cohort on every page load.** A live evaluation over a large
  population is heavy, and the snapshot already holds the numbers.
- **Unset values use sentinels:** counts can come back as `-1`, and names and birth dates as
  `"n/a"`. Normalize them once ([sentinel-values-not-null.md](sentinel-values-not-null.md)).
- **Snapshot timestamps carry no timezone,** so treat them as UTC before formatting.
- **History and campaign features only make sense once the cohort is Active.** While it's
  Initializing, show "building" and let the user refresh.

## Related

- [cohort-definitions.md](cohort-definitions.md) — the lifecycle and states.
- [cohort-campaigns.md](cohort-campaigns.md) — the targeted counts come from the launched campaign.
- [bulk-read-and-export.md](bulk-read-and-export.md) — why async export jobs aren't a foundation.
