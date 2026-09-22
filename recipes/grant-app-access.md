# Grant an organization access to your application

**Use when:** an organization needs to be able to launch/see your **external application** — a
private (`isPublic: false`) app refuses to launch for any organization not on its allow-list.
**Routes:** `PUT /api/v2/external-application/{appId}/allowed-organizations` → [route docs](https://agents.1health.io/public/prod/api/manifest.md) · read-back is a separate grid endpoint — confirm the exact path in the [manifest](https://agents.1health.io/public/prod/api/manifest.md) before coding it (see Gotchas)
**Reference code:** [`lib/onehealth/allowed-organizations.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-med-adherence-bcbsm/blob/main/lib/onehealth/allowed-organizations.ts) · [`lib/expertdx/registration.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/lib/expertdx/registration.ts#L236)
**Seen in:** med-adherence, expertdx, pcp-tcm

## Pattern

1. Know your application's id (from registering it — see
   [register-console-application.md](register-console-application.md) — or from your platform
   configuration).
2. PUT the allowed-organizations endpoint with the id(s) to add/remove in one call; expect
   **204 No Content** on success.
3. Decide **which id the endpoint wants** for your case — some deployments key this off the
   partnership-record id rather than the raw organization id (see
   [partner-invitation-and-pin.md](partner-invitation-and-pin.md)). Confirm empirically; passing the
   wrong kind of id can appear to succeed while granting the wrong record.
4. There is **no GET** on this path. To verify or list current access, read it back through the
   grid/list surface instead.
5. Treat a failed grant as **non-fatal but visible**: let the rest of onboarding continue, and
   surface a manual follow-up — this call can require a higher privilege than your caller holds.

## Minimal example

```ts
const EXTERNAL_APP_ID = process.env.EXTERNAL_APP_ID! // your registered application's id

async function grantAccess(orgOrPartnershipId: number) {
  const res = await callApi(
    "app-access/grant",
    `/api/v2/external-application/${EXTERNAL_APP_ID}/allowed-organizations`,
    {
      method: "PUT",
      body: JSON.stringify({ organizationIdsToAdd: [orgOrPartnershipId], organizationIdsToRemove: [] }),
    },
  )
  if (!res.success) {
    // Non-fatal by design — see Gotchas. Surface for manual follow-up instead of throwing.
    console.warn(`App access not granted for ${orgOrPartnershipId}: ${res.error}`)
    return false
  }
  return true
}
```

## Gotchas

- **`GET` on the write path 405s.** Reading current access back is a *different* endpoint (a grid
  query), not a GET on `/external-application/{appId}/allowed-organizations`.
- **A privileged service key can still 403 here** — this endpoint has been observed to require an
  admin user of the *app's own* owning tenant, not just any elevated credential.
- **Org id vs. partnership id is not interchangeable everywhere** — verify which one your target
  deployment expects; the call can "succeed" while silently granting the wrong record.
- Without this grant, an otherwise fully-registered organization can complete registration and still
  be unable to launch your app — don't treat it as an optional last step.

## Related

- [self-service-org-onboarding-by-npi.md](self-service-org-onboarding-by-npi.md), [partner-invitation-and-pin.md](partner-invitation-and-pin.md), [register-console-application.md](register-console-application.md)
- [share-with-partner-org.md](share-with-partner-org.md) — sharing a specific record vs. granting whole-app access.
