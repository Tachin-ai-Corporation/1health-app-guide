# Partner invitation + PIN

**Use when:** you need to invite an organization into a partnership with your tenant and obtain a
shareable registration PIN — including recovering an invitation that was previously rejected.
**Routes:** `POST /api/v2/organization/partner/invitation` → [agents.md](https://agents.1health.io/public/prod/api/v2/organization/partner/invitation/agents.md) · `PUT /api/v2/organization/partnership/{id}/status` → [route docs](https://agents.1health.io/public/prod/api/manifest.md)
**Reference code:** [`lib/onehealth/organization-list.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-med-adherence-bcbsm/blob/main/lib/onehealth/organization-list.ts#L395)
**Seen in:** med-adherence; the same call opens step 3 of [self-service-org-onboarding-by-npi.md](self-service-org-onboarding-by-npi.md) (pcp-tcm, expertdx)

## Pattern

1. POST the partner invitation with the organization id, a display name, and a recipient email.
   Treat **200, 201, and 409 as all "success"** — 409 typically means the partnership already exists.
2. Parse the PIN **only from a successful response body** — never read a PIN-shaped field out of an
   error body.
3. If the target organization previously **rejected** the partnership, the platform refuses to
   re-invite it. Detect that specific error (by message text, not just status code), PUT the
   partnership's status back to `Pending` — as a **query parameter**, not a body field — then retry
   the invitation once.
4. Capture the **partnership-record id** the response returns alongside the PIN. Downstream calls
   (like granting app access) commonly expect this id, not the raw organization id — see
   [grant-app-access.md](grant-app-access.md).

## Minimal example

```ts
async function invitePartner(orgId: number, name: string, email: string) {
  let res = await callApi<{ invitationPin?: string; pin?: string; id?: number }>(
    "partner/invite",
    "/api/v2/organization/partner/invitation",
    { method: "POST", body: JSON.stringify({ partnerOrganizationId: orgId, name, email }) },
  )

  if (!res.success && isRejectedPartnershipError(res.error)) {
    await callApi("partner/reset", `/api/v2/organization/partnership/${orgId}/status?partnershipStatus=Pending`, {
      method: "PUT",
    })
    res = await callApi("partner/invite retry", "/api/v2/organization/partner/invitation", {
      method: "POST",
      body: JSON.stringify({ partnerOrganizationId: orgId, name, email }),
    })
  }
  if (!res.success) throw new Error(`Could not invite ${name}: ${res.error}`)

  const pin = res.data?.invitationPin ?? res.data?.pin
  if (!pin) throw new Error(`1health did not return a PIN for ${name}`)
  return { pin: String(pin), partnershipId: res.data?.id ?? null }
}
```

## Gotchas

- **409 is success here, not failure** — it means the invitation/partnership already exists; proceed
  as if the call succeeded.
- **A Rejected partnership silently blocks re-invitation** until you reset its status — and the
  target status travels as a query param, which is easy to miss when reading the endpoint casually.
- **Field names for the PIN and the partnership id are not perfectly uniform** — check the documented
  field first, then fall back defensively; never guess a value out of an unrelated field (a hash, a
  URL slug) just because it happens to look similar.
- **Never surface the PIN anywhere client-visible** (logs, error toasts) before it has actually been
  delivered out-of-band — see [deep-link-invite-url.md](deep-link-invite-url.md).

## Related

- [self-service-org-onboarding-by-npi.md](self-service-org-onboarding-by-npi.md), [grant-app-access.md](grant-app-access.md), [deep-link-invite-url.md](deep-link-invite-url.md), [org-claim-status-lookup.md](org-claim-status-lookup.md)
- [share-with-partner-org.md](share-with-partner-org.md), [partner-org-typeahead.md](partner-org-typeahead.md) — related partner-organization mechanics.
