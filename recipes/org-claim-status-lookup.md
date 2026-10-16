# Org claim/partnership status lookup, PII-safe

**Use when:** you need to show whether a partner organization has already been "claimed" (has an
active tenant/admin) and whether it's partnered with you — without ever leaking un-partnered
contact PII to the browser.
**Routes:** `GET /api/v2/organization/list` → [agents.md](https://agents.1health.io/public/prod/api/v2/organization/list/agents.md) (search) · `GET /api/v2/organization/{id}` → [agents.md](https://agents.1health.io/public/prod/api/v2/organization/agents.md) (authoritative per-org `claimed` flag)
**Reference code:** none public — see the Minimal example.
**Seen in:** A medication-adherence app

## Pattern

1. Search by **exact name** (trimmed, case-insensitive) rather than trusting `results[0]` from a
   fuzzy list search — a broad search can resolve to a sibling organization.
2. Don't trust list-level fields (e.g. a tenant-id or partnership-status column) to distinguish
   "fully onboarded" from "invited-but-unclaimed shell" — on some datasets they're uniform across
   *every* row and carry no signal at all. Verify empirically against known orgs before relying on
   any field.
3. Call the **single-org detail** endpoint and use its boolean `claimed` field as the authoritative
   signal instead.
4. Only when claimed **and** partnered with your tenant, return real contact details. Otherwise
   obfuscate (or omit) them — server-side, before the response ever reaches the browser.
5. Treat `claimed` as **eventually consistent**: a just-onboarded org can briefly read unclaimed. A
   lookup that re-runs on next view self-heals, so don't cache the result long.
6. On any ambiguous or failed lookup, default to the safe, permissive state (unclaimed/selectable)
   rather than blocking the UI on an unverifiable check.

## Minimal example

```ts
import { callApi } from "@/lib/api"

interface OrgSearchHit {
  organization?: { id?: number; name?: string; partnershipStatus?: unknown; personContacts?: unknown[] }
}

const normalizedName = (name = "") => name.trim().toLowerCase()

/** Exact (trimmed, case-insensitive) name match — never just the first fuzzy hit. */
async function findOrgByExactName(orgName: string) {
  const res = await callApi<{ data: OrgSearchHit[] }>(
    "org/claim-status.search",
    `/api/v2/organization/list?name=${encodeURIComponent(orgName)}&claimFilter=claim-and-pending&page=0&size=8`,
  )
  const hits = res.success ? (res.data?.data ?? []) : []
  return hits.find((hit) => normalizedName(hit.organization?.name) === normalizedName(orgName))?.organization
}

/** The single-org detail's `claimed` flag is the authoritative signal. */
async function readClaimedFlag(orgId: number): Promise<boolean> {
  const res = await callApi<{ claimed?: boolean }>("org/claim-status.detail", `/api/v2/organization/${orgId}`)
  return res.data?.claimed === true
}

async function getClaimStatus(orgName: string, viewerTenantId: string) {
  const org = await findOrgByExactName(orgName)
  if (!org?.id || !(await readClaimedFlag(org.id))) return { status: "unclaimed" as const }

  const firstContact = org.personContacts?.[0]
  // Your helper: does this org's partnership status name your tenant as an active partner?
  return hasActivePartnership(org.partnershipStatus, viewerTenantId)
    ? { status: "claimed" as const, partnered: true, contact: fullContact(firstContact) }
    : { status: "claimed" as const, partnered: false, contact: obfuscatedContact(firstContact) }
}
```

## Gotchas

- **List-endpoint fields you'd expect to be authoritative can be uniformly unhelpful** across an
  entire result set — confirm against known orgs before trusting one, rather than assuming the field
  name implies correctness.
- **PII redaction must happen server-side.** Never send raw contact info to the client and redact
  in the UI layer — a network tab makes that no protection at all.
- **`claimed` is eventually consistent** right after an onboarding write — don't treat a `false` seen
  immediately after inviting an org as permanent.
- Prefer an exact (trimmed, case-insensitive) name match over `results[0]` — fuzzy search ranking is
  not guaranteed to put the right org first.

## Related

- [self-service-org-onboarding-by-npi.md](self-service-org-onboarding-by-npi.md), [partner-invitation-and-pin.md](partner-invitation-and-pin.md)
- [sanitizing-bff-proxy.md](sanitizing-bff-proxy.md) — the same "normalize + redact server-side" shape applied elsewhere.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md).
