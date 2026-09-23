# Toggle partnership status and relationship types independently

**Use when:** you need to represent that two organizations are "partnered" — beyond a single
Approved/Pending/Rejected status, a handful of relationship types (can order from, is a service
provider for, etc.) can each be switched on or off without touching the others.
**Routes:** `GET /api/v2/organization/partnership` → [agents.md](https://agents.1health.io/public/prod/api/v2/organization/partnership/agents.md) (read) · `PUT /api/v2/organization/partnership/{orgId}/status` → [agents.md](https://agents.1health.io/public/prod/api/v2/organization/partnership/_orgId_/status/agents.md) (overall status) · `PUT /api/v2/organization/partnership/{orgId}/service/{service}` → [agents.md](https://agents.1health.io/public/prod/api/v2/organization/partnership/_orgId_/service/agents.md) (one relationship type)
**Reference code:** [`partners.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-secure-share/blob/main/lib/api/partners.ts#L73) (the read) — none public for the status/service toggles; see the Minimal example.
**Seen in:** secure-share (the read); 1health platform usage (the status/service toggles)

## Pattern

1. Treat "partnered" as **two layers**, not one flag: an overall partnership **status**
   (Pending/Approved/Rejected) gates whether the relationship exists at all; independently, a small
   fixed set of relationship **types** — ordering-entity, service-provider, can-order-from,
   uses-services-of — can each be active or inactive without touching the status or each other.
2. Read both layers with **one flexible call**: `GET .../partnership`, filtered by the `relKeys` you
   care about, `direction` (`Inbound`/`Outbound`), and `partnershipStatus`. The same read can power
   an approved-partners list, an incoming-invites tab, and an outgoing-invites badge count — vary the
   filters, don't build three separate integrations.
3. Change the **overall status** with a query-param PUT and an empty body — accept, reject, or reset
   back to `Pending` (e.g. to allow re-inviting a previously-rejected org — see
   [partner-invitation-and-pin.md](partner-invitation-and-pin.md)).
4. Toggle **one relationship type at a time** with its own query-param PUT — this never changes the
   overall status or any other relationship type.
5. Don't invent your own relationship-type strings. `relKeys` is a small, fixed platform vocabulary
   — request only the ones your app's domain actually cares about; an unrecognized or wrong key
   silently returns no match for that row instead of an error.

## Minimal example

```ts
import { callApi } from "@/lib/api"

const REL_KEYS = [
  "OrganizationCanOrderFromOrganization",
  "OrganizationIsServiceProviderForOrganization",
  "OrganizationUsesServicesOfProviderOrganization",
  "OrganizationHasOrderingEntityOrganization",
] as const

// Read: one call powers "approved partners," "incoming invites," and "outgoing invites" alike.
async function listPartnerships(direction: "Inbound" | "Outbound", status: string[]) {
  const params = new URLSearchParams()
  REL_KEYS.forEach((k) => params.append("relKeys", k))
  status.forEach((s) => params.append("partnershipStatus", s))
  params.set("direction", direction)
  const res = await callApi<{ data: Array<{ organization: { id: number; name: string }; partnerships: Array<{ key: string; isActive: boolean }> }> }>(
    "partnership/list", `/api/v2/organization/partnership?${params}`,
  )
  return res.success ? res.data!.data : []
}

// Overall status: query param, empty body.
async function setPartnershipStatus(orgId: number, status: "Approved" | "Rejected" | "Pending") {
  await callApi("partnership/status", `/api/v2/organization/partnership/${orgId}/status?partnershipStatus=${status}`, {
    method: "PUT",
  })
}

// One relationship type at a time — independent of status and of every other type.
async function setPartnershipService(orgId: number, service: string, isActive: boolean) {
  await callApi("partnership/service", `/api/v2/organization/partnership/${orgId}/service/${service}?isActive=${isActive}`, {
    method: "PUT",
  })
}
```

## Gotchas

- Both PUTs key off the **organization** id in the path — not a separate partnership-record id —
  and both send their target as a **query parameter with an empty body**, easy to get backwards
  from typical REST expectations.
- `relKeys` is a small fixed vocabulary (four values) — a typo returns an empty `partnerships` match
  for that row, not an error.
- A `Rejected` status blocks re-invitation until it's reset back to `Pending` — see
  [partner-invitation-and-pin.md](partner-invitation-and-pin.md).
- Deactivating a relationship type doesn't touch the overall status or any sibling type — an org can
  be `Approved` overall with every relationship type switched off.
- The docs pin down `relKeys`/`direction`/`partnershipStatus` precisely but don't spell out every
  field on each row beyond a `partnerships: [{ key, isActive }]` array per relationship type — read
  anything else defensively.

## Related

- [partner-invitation-and-pin.md](partner-invitation-and-pin.md) — creating the partnership this
  recipe manages.
- [partner-org-typeahead.md](partner-org-typeahead.md) — resolving the organization id you toggle.
- [message-a-partner-contact-point.md](message-a-partner-contact-point.md) — notifying a partner
  once the relationship is in place.
- [share-with-partner-org.md](share-with-partner-org.md) — sharing a specific record vs. this
  org-level relationship.
