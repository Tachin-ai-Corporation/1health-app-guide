# Partner org typeahead

**Use when:** a user needs to pick a partner organization from a search box (to share with,
invite, or address something to) instead of being handed a raw org id.
**Routes:** `GET /api/v2/organization/partnership?partnershipStatus=Approved&searchText=&relKeys=…`
(tenant-wide search) → [agents.md](https://agents.1health.io/public/prod/api/v2/organization/partnership/agents.md)
· `POST /api/v2/query` (campaign-scoped list) →
[agents.md](https://agents.1health.io/public/prod/api/v2/query/agents.md)
**Reference code:** [`partners.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-secure-share/blob/main/lib/api/partners.ts#L73) (tenant-wide search) ·
[`query.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-med-adherence-bcbsm/blob/main/lib/api/query.ts#L153) (`fetchInvitableOrganizations`, campaign-scoped)
**Seen in:** secure-share, med-adherence

## Pattern

1. **Decide the population first.** "Every approved partner on the tenant" (the partnership
   endpoint) and "organizations already tied to one campaign" (`/query` on `Organization`, filtered
   by the campaign) are different sets and different endpoints — picking the wrong one either
   floods the dropdown with irrelevant orgs or misses the one the user wants.
2. **Tenant-wide search:** call the partnership endpoint with `partnershipStatus=Approved`, the
   user's `searchText`, and the `relKeys` your app cares about (which partnership relationship
   *types* count — these are platform/domain-specific, not a universal list). Debounce the input
   (around 300ms) so each keystroke doesn't fire a request.
3. **Campaign-scoped search:** fetch the (small, bounded) list of organizations already on the
   campaign ONCE, projecting only the couple of attributes you need, then filter client-side as the
   user types — cheaper than a server round trip per keystroke once the candidate set is small.
4. **Request only attributes the type actually supports.** Some plausible-looking fields (a
   partnership-status flag on `Organization`, for instance) are rejected by `/query` with a 400
   "Unknown attribute key" — keep the projection minimal and verified.
5. **De-duplicate by an id (+ category) key** — the same organization can appear under more than
   one relationship key or type bucket.
6. **Render enough to disambiguate** — name plus a category/type badge (and a logo/initials avatar
   if available); organization names alone collide often enough to matter.

## Minimal example

```ts
import { fetchPartnerships } from "@/lib/api"

// Tenant-wide, server-side debounced search.
async function searchPartners(searchText: string) {
  const res = await fetchPartnerships({
    searchText,
    status: "Approved",
    relKeys: ["OrganizationCanOrderFromOrganization", "OrganizationUsesServicesOfProviderOrganization"],
  })
  return res.success ? res.data!.data.map((p) => p.organization) : []
}
```

```ts
import { runQueryRows, eq, findAttr } from "@/lib/api"

// Campaign-scoped: fetch once, filter client-side as the user types.
async function loadCampaignOrganizations(campaignId: number) {
  const rows = await runQueryRows({
    key: "Organization",
    attributes: ["id", "name", "type"],   // keep this minimal — see Gotchas
    filter: eq("workflowCampaignId", campaignId),
    limit: 500,
  })
  return rows.map((r) => ({
    id: findAttr<number>(r, "id"),
    name: findAttr<string>(r, "name"),
    type: findAttr<string>(r, "type"),
  }))
}
```

## Gotchas

- **`relKeys` values are platform/domain relationship-type strings, not a fixed universal list** —
  confirm the set your tenant actually uses; an empty or wrong set silently returns nothing rather
  than an error.
- **`Organization` via `/query` rejects some plausible attributes** (a partnership-status or
  tenant-id-shaped field) with a 400 "Unknown attribute key" — request only fields you've verified
  the type supports.
- **The two strategies return different populations** — don't reuse one implementation for both
  "search everyone" and "search this campaign's orgs" use cases.
- **Debounce the server-search variant; fetch-once-and-filter the client variant** — debouncing a
  client-side filter just adds latency the network round trip didn't require.
- **Dedupe by id, not by display name** — names are not guaranteed unique at scale.

## Related

- [share-with-partner-org.md](share-with-partner-org.md) (F1) — what you do with the id once
  resolved.
- [partner-invitation-and-pin.md](partner-invitation-and-pin.md) — inviting an organization that isn't a partner yet.
- [self-service-org-onboarding-by-npi.md](self-service-org-onboarding-by-npi.md)
- [query-the-data-graph.md](query-the-data-graph.md) — the `/query` mechanics behind the
  campaign-scoped variant.
