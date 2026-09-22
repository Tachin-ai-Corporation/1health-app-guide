# Bulk assignment

**Use when:** you need to assign or unassign one or more users (e.g. care coordinators) across a batch of records selected in a grid, and show who's already assigned across the whole selection.
**Routes:** `POST /api/v2/journey/assign-users` → [agents.md](https://agents.1health.io/public/prod/api/v2/journey/assign-users/agents.md) · `POST /api/v2/journey/unassign-users` → [agents.md](https://agents.1health.io/public/prod/api/v2/journey/unassign-users/agents.md)
**Reference code:** [`lib/api/journey.ts`](https://github.com/Tachin-ai-Corporation/v0-trc-care-coordinator/blob/main/lib/api/journey.ts) · [`use-coordinator-management.ts`](https://github.com/Tachin-ai-Corporation/v0-trc-care-coordinator/blob/main/components/data-grid/hooks/use-coordinator-management.ts) (the client-side intersection)
**Seen in:** trc-care-coordinator

## Pattern

1. Model assignment as two symmetric bulk endpoints — one to add, one to remove — each taking arrays of target record ids and user ids in a single call.
2. Wrap the payload in an **array containing one object**, even for a single call — matches this bulk-operation body convention.
3. To show "who's currently assigned" across a multi-record selection, don't call a special endpoint: read each selected record's own assignment list (you likely already have it from the grid row) and **intersect** the per-record user-id sets client-side — that intersection is your "assigned to every selected record" set.
4. Distinguish removal failures from generic failures: "unassign" fails when a user isn't assigned to every record in the batch, which deserves a specific message ("select records with matching assignments"), not a generic error.

## Minimal example

```ts
import { authFetch, getOneHealthBaseUrl } from "@/lib/auth-client"

// ASSIGN — array-wrapped even for one call.
async function assignUsersToJourneys(journeyIds: number[], userIds: number[]): Promise<void> {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/v2/journey/assign-users`, {
    method: "POST",
    body: JSON.stringify([{ journeyIds, userIds }]),
  })
  if (!response.ok) throw new Error(`Assign failed: ${response.status}`)
}

// UNASSIGN — same shape, opposite direction.
async function removeUsersFromJourneys(journeyIds: number[], userIds: number[]): Promise<void> {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/v2/journey/unassign-users`, {
    method: "POST",
    body: JSON.stringify([{ journeyIds, userIds }]),
  })
  if (!response.ok) throw new Error(`Unassign failed: ${response.status}`)
}

// "Assigned to every selected record" — intersect client-side; no such endpoint exists.
function usersAssignedToAll(selectedRecords: { assignedUserIds: number[] }[]): Set<number> {
  const [first, ...rest] = selectedRecords.map((r) => new Set(r.assignedUserIds))
  if (!first) return new Set()
  return new Set([...first].filter((id) => rest.every((set) => set.has(id))))
}
```

## Gotchas

- Both endpoints take the same wrapper shape — an array holding one `{ journeyIds, userIds }` object — never a bare `{ journeyIds, userIds }`.
- Unassigning a user who isn't actually on every targeted record fails with a 400/404-shaped error — catch it and tell the user which part of the selection is mismatched.
- There's no bulk "who is assigned across this selection" endpoint — derive it client-side from data you already have.
- Resolve candidates for an assignment picker through a server-searched, debounced user lookup — don't try to page through the full org user list for a typeahead.

## Related

- [bulk-tagging.md](bulk-tagging.md) — sibling bulk grid action, same array-wrapped-body family.
- [saved-grid-views.md](saved-grid-views.md) — the grid these actions typically hang off.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md).
