# Read the right org/tenant profile for the id you hold

**Use when:** you need "the org's profile" but only have one kind of id in hand — your own
session, a subdomain, a tenant id, or an organization id — and picking the wrong read either 404s
or silently returns the wrong record's shape.
**Routes:** `GET /api/v2/tenant` → [agents.md](https://agents.1health.io/public/prod/api/v2/tenant/agents.md) (own tenant, authenticated) · `GET /api/v2/public/tenant/config` → [agents.md](https://agents.1health.io/public/prod/api/v2/public/tenant/config/agents.md) (public, by subdomain) · `GET /api/v2/tenant/sys-config` → [agents.md](https://agents.1health.io/public/prod/api/v2/tenant/sys-config/agents.md) (batch, by tenant id) · `GET /api/v2/organization/{id}` → [agents.md](https://agents.1health.io/public/prod/api/v2/organization/agents.md) (by organization id)
**Reference code:** [`organization-list.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-med-adherence-bcbsm/blob/main/lib/onehealth/organization-list.ts#L666) (the by-organization-id read) — none public for the other three reads; see the Minimal example.
**Seen in:** med-adherence (by-organization-id read); 1health platform usage (the other three)

## Pattern

1. **Work out which id you actually hold first** — your own authenticated session (no id needed),
   a tenant's subdomain (pre-login), a tenant id (e.g. from a partnership row), or an organization
   id (e.g. from a search result). Each is read by a different, non-interchangeable call.
2. **Your own tenant, authenticated:** `GET /api/v2/tenant` returns your tenant context with a
   nested `organization` object.
3. **Pre-login, by subdomain:** `GET /api/v2/public/tenant/config` is unauthenticated and resolves
   the tenant from the request's own origin, not a query parameter — call it against the target
   tenant's subdomain, not your app's default base URL. It's what a not-yet-logged-in visitor's UI
   uses to pick branding and registration-flow config before any session exists.
4. **A partner (or any other) tenant, by TENANT id:** `GET /api/v2/tenant/sys-config` accepts one or
   more tenant ids in a single call and nests a full `organization` object per tenant — the read
   side of editing a partner's profile (tax id, CLIA, NPI, address).
5. **A partner (or any other) org, by ORGANIZATION id:** `GET /api/v2/organization/{id}` returns a
   smaller, admin-facing shape, including the authoritative `claimed` boolean — see
   [org-claim-status-lookup.md](org-claim-status-lookup.md).

## Primary vs fallback

- **Primary — `GET /api/v2/tenant/sys-config` (by TENANT id):** use when you hold a tenant id —
  e.g. from a partnership row — and need the nested organization object to display or edit a
  partner's editable profile.
- **Fallback — `GET /api/v2/organization/{id}` (by ORGANIZATION id):** use when you only hold an
  organization id and need admin-facing fields, including the authoritative `claimed` flag.
- These two ids are **not interchangeable** — pick the call that matches the id you actually hold,
  not the one you'd prefer to have; a partnership list row commonly carries both, but each of these
  two reads only accepts one of them.

## Minimal example

```ts
import { callApi } from "@/lib/api"

// Your own tenant — authenticated, no id required.
async function getMyTenant() {
  const res = await callApi<{ id: number; organization?: { id: number; name: string } }>(
    "tenant/mine", "/api/v2/tenant",
  )
  return res.success ? res.data : null
}

// Pre-login, by subdomain — unauthenticated. Call this against the TARGET tenant's own base URL;
// the tenant is resolved from the calling origin, not a parameter.
async function getPublicTenantConfig() {
  const res = await callApi<{ tenantName?: string; publicUrlLogo?: string }>(
    "tenant/public-config", "/api/v2/public/tenant/config",
  )
  return res.success ? res.data : null
}

// Have a TENANT id (e.g. from a partnership row) — batch-capable, nests `organization`.
async function getOrgProfileByTenantId(tenantId: number) {
  const res = await callApi<Array<{ tenantId: number; organization?: { id: number; taxId?: string } }>>(
    "tenant/sys-config", `/api/v2/tenant/sys-config?${encodeURIComponent("Tenant IDs")}=${tenantId}`,
  )
  return res.success ? res.data?.[0]?.organization ?? null : null
}

// Have an ORGANIZATION id (e.g. from a search result) — admin-facing fields, incl. `claimed`.
async function getOrgProfileByOrgId(orgId: number) {
  const res = await callApi<{ id: number; claimed?: boolean; npi?: string }>(
    "organization/detail", `/api/v2/organization/${orgId}`,
  )
  return res.success ? res.data : null
}
```

## Gotchas

- `tenant/sys-config`'s query parameter name is literally `Tenant IDs` — with a space, URL-encoded
  — not a normal array or repeated param; copy it exactly rather than guessing a convention.
- `GET /organization/{id}` isn't separately listed in the route manifest — it's documented as a
  child heading on the plain `/organization` collection page (the "get my organization" route).
  Don't confuse the two: no id returns *your own* org; an id returns the *target* org's profile.
- `public/tenant/config` takes no query parameters — it infers the tenant from the request's own
  origin/subdomain, so the base URL you call it against **is** the selector.
- `tenant/sys-config` also accepts `includeAllRelations=true` to pull in person contacts and NPI
  relations in the same call — reach for it only when you need those, since it's a heavier read.

## Related

- [org-claim-status-lookup.md](org-claim-status-lookup.md) — consumes the by-organization-id
  read's `claimed` field.
- [org-identity-and-branding-assets.md](org-identity-and-branding-assets.md) — writing the fields
  this recipe reads back.
- [partner-invitation-and-pin.md](partner-invitation-and-pin.md), [partnership-relationship-types.md](partnership-relationship-types.md) — where a tenant id or organization id typically comes from.
- [tenant-provisioning.md](tenant-provisioning.md) — creating the tenant this recipe reads.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md).
