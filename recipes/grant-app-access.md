# Grant an organization access to your application

**Use when:** an organization needs to be able to launch/see your **external application** — a
private (`isPublic: false`) app refuses to launch for any organization not on its allow-list.
**Routes:** `POST /api/v3/public/user/associate-if-registered?openApp={appId}` → [agents.md](https://agents.1health.io/public/prod/api/v3/public/user/associate-if-registered/agents.md) (primary, invite-time grant) · `PUT /api/v2/external-application/{appId}/allowed-organizations` (not yet in the published docs) (fallback, after the fact) · `POST /api/v3/health/grid/external-application/{appId}/allowed-organizations` (not yet in the published docs) (read-back — there is no GET)
**Reference code:** [`lib/onehealth/allowed-organizations.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-med-adherence-bcbsm/blob/main/lib/onehealth/allowed-organizations.ts) · [`lib/expertdx/registration.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/lib/expertdx/registration.ts#L236)
**Seen in:** med-adherence, expertdx, pcp-tcm

> **⚠ Not yet in 1health's published API docs:** `PUT /api/v2/external-application/{appId}/allowed-organizations`, `POST /api/v3/health/grid/external-application/{appId}/allowed-organizations`. 1health supports them for third-party apps, but agents.1health.io has no page for them yet — the shapes shown here come from working apps. Test them against demo before you rely on them.

## Pattern

1. **Prefer granting access at invitation time.** If you control the invitation/registration link,
   append `?openApp=<appId>` to the accept-invitation call — `POST /api/v3/public/user/associate-if-registered`
   documents this: when the invitee's account already exists and is verified, the platform grants
   that application's access to the invited organization as part of completing the attachment, with
   no separate privileged call at all. See [partner-invitation-and-pin.md](partner-invitation-and-pin.md) /
   [self-service-org-onboarding-by-npi.md](self-service-org-onboarding-by-npi.md) for where this call
   sits in a full invite flow.
2. **`openApp` is not confirmed on the brand-new-registration path** (`POST /v3/public/user/register`)
   — only `associate-if-registered` documents it. If your invitee might be a first-time registrant
   rather than an already-verified account, don't assume the param carries through; verify against
   demo, or fall back to step 3 for that org.
3. Outside an invitation flow — or when you need to grant/revoke in bulk, after the fact — know your
   application's id (from registering it — see
   [register-console-application.md](register-console-application.md) — or from your platform
   configuration) and PUT the allowed-organizations endpoint with the id(s) to add/remove in one
   call; expect **204 No Content** on success.
4. Decide **which id the endpoint wants** for your case — some deployments key this off the
   partnership-record id rather than the raw organization id (see
   [partner-invitation-and-pin.md](partner-invitation-and-pin.md)). Confirm empirically; passing the
   wrong kind of id can appear to succeed while granting the wrong record.
5. There is **no GET** on the PUT's own path. To verify or list current access, read it back through
   `POST /api/v3/health/grid/external-application/{appId}/allowed-organizations` (a grid-shaped
   query, not a plain list).
6. Treat a failed grant as **non-fatal but visible**: let the rest of onboarding continue, and
   surface a manual follow-up — this call can require a higher privilege than your caller holds.

## Primary vs fallback

- **Primary — `openApp` at invite/association time:** request access as part of accepting the
  invitation; nothing extra to call, and no elevated privilege needed beyond what the invitation
  itself already required.
- **Fallback — `PUT .../allowed-organizations`:** use it when granting outside an invitation flow
  entirely (an already-registered org, added later) or when you need to grant/revoke several
  organizations in one bulk call.

## Minimal example

```ts
const EXTERNAL_APP_ID = process.env.EXTERNAL_APP_ID! // your registered application's id

// Primary: grant access as a side effect of accepting the invitation.
async function acceptInviteWithAppAccess(email: string, verificationToken: string, orgUuid: string, invitationPin: string) {
  const res = await callApi<{ user: { emailRegistered: boolean; emailVerified: boolean }; organization: { id: number } | null }>(
    "invite/associate",
    `/api/v3/public/user/associate-if-registered?openApp=${EXTERNAL_APP_ID}`,
    { method: "POST", body: JSON.stringify({ email, verificationToken, orgUuid, invitationPin }) },
  )
  if (!res.success) throw new Error(res.error)
  return res.data // `organization` is populated only when an already-verified account was attached
}

// Fallback: grant access outside an invitation flow, or in bulk, after the fact.
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

- **`openApp` is documented on `associate-if-registered` only** — don't assume it also works on the
  brand-new-registration endpoint (`/v3/public/user/register`); that's unconfirmed.
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
