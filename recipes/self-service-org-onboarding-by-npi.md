# Self-service org onboarding by NPI

**Use when:** an unauthenticated visitor needs to provision their own organization in 1health by
proving a real-world professional identifier (e.g. an NPI), then be handed a link to finish
claiming it — before any 1health session exists for them.
**Routes:** 1health's own `GET /api/v2/public/npi/list` → [agents.md](https://agents.1health.io/public/prod/api/v2/public/npi/list/agents.md) (primary identity lookup) · external `GET https://npiregistry.cms.hhs.gov/api/` (public registry, not 1health — fallback when the verification itself must be authoritative) · `GET /api/v2/organization/list` → [agents.md](https://agents.1health.io/public/prod/api/v2/organization/list/agents.md) · `POST /api/v2/organization/partner/invitation` → [agents.md](https://agents.1health.io/public/prod/api/v2/organization/partner/invitation/agents.md) · `PUT /api/v2/external-application/{appId}/allowed-organizations` (not yet in the published docs) · `POST /api/v2/url-mapping/generate` (not yet in the published docs) (+ the contact-point sub-calls — confirm exact shape via the [manifest](https://agents.1health.io/public/prod/api/manifest.md) before coding them)
**Reference code:** [`lib/expertdx/registration.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/lib/expertdx/registration.ts) · [`app/api/register/provision/route.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/app/api/register/provision/route.ts) · [`lib/npi/registry.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/lib/npi/registry.ts)
**Seen in:** pcp-tcm, expertdx (full NPI → org → invite chain); med-adherence (the invite/PIN/grant-access portion, without the NPI lookup)

> **⚠ Not yet in 1health's published API docs:** `PUT /api/v2/external-application/{appId}/allowed-organizations`, `POST /api/v2/url-mapping/generate`. 1health supports them for third-party apps, but agents.1health.io has no page for them yet — the shapes shown here come from working apps. Test them against demo before you rely on them.

## Pattern

This is the "big cluster" recipe: it orchestrates several smaller ones (linked below) into one
self-service flow. It necessarily runs **unauthenticated and server-side**, before any user token
exists — read the Gotchas before you build this.

1. **Verify the identifier server-side**, even if the client already checked. Prefer 1health's own
   `public/npi/list` mirror — one unauthenticated call gives you both a "this looks like a real NPI"
   signal and the platform-native id (its `.id`, not the 10-digit `.npi` number) that org-create and
   partner-invite endpoints expect as `npiId`/`organizationNpiId`, so there's no separate step to
   bridge "the number I verified" into "the id 1health wants." Fall back to the authoritative
   external registry (below) only when the verification itself — not just the lookup — must be
   against the federal source, e.g. for a compliance requirement. Reject invalid/inactive
   identifiers before touching 1health any further.
2. **Look before you create.** Search 1health for an Organization already carrying that identifier,
   then re-check the exact field on any candidate — a fuzzy text match can return a neighbor. See
   [look-then-create.md](look-then-create.md).
3. **Create-or-link the partner Organization.** Call the partner-invitation endpoint, passing the
   existing org's id when step 2 found one so the platform links it instead of minting a duplicate.
   Capture the invitation PIN and the partnership id. See
   [partner-invitation-and-pin.md](partner-invitation-and-pin.md).
4. **Grant the org access to your application immediately** — an org that isn't on your app's
   allow-list can finish registering but can never launch it. See
   [grant-app-access.md](grant-app-access.md).
5. **Attach a verified contact point** (e.g. a mobile number), using look-then-create so a retry
   never collides with itself.
6. **Mint a branded deep-link** tied to the same invitation and send it over the contact point. The
   PIN travels out-of-band (SMS/email) — never in your JSON response. See
   [deep-link-invite-url.md](deep-link-invite-url.md).
7. **Report progress as you go.** Five-plus sequential platform calls behind one button press is
   exactly when a bare spinner reads as broken. See
   [ndjson-progress-streaming.md](ndjson-progress-streaming.md).
8. Hand back only what the browser needs to show a result (a name, a link). The user finishes
   registering at that link, entering the PIN that arrived on their own device.

## Primary vs fallback

- **Primary — 1health's own `GET /api/v2/public/npi/list`:** unauthenticated, and its `.id` field is
  already the value org-create/partner-invitation endpoints want for `npiId`/`organizationNpiId` —
  no separate id-bridging step needed.
- **Fallback — the external CMS registry (`npiregistry.cms.hhs.gov`):** switch to it only when the
  verification itself, not just the lookup, must be against the authoritative federal source (e.g. a
  compliance requirement) — then still resolve 1health's own id separately before writing anything
  back to 1health.

## Minimal example

```ts
// Server-only. Runs unauthenticated, under a scoped service credential — never the browser's
// token, because no user session exists yet. See split-identity-service-key.md.
import { platformServiceCall } from "@/lib/platform/service-client"
import { lookupExternalIdentity } from "@/lib/external-registry"

const APP_ID = process.env.EXTERNAL_APP_ID! // your registered application's id

export async function provisionOrganization(
  rawIdentifier: string,
  contactValue: string,
  onEvent: (e: { step: string; label: string }) => void,
) {
  const identity = await lookupExternalIdentity(rawIdentifier) // throws on invalid/inactive

  onEvent({ step: "search", label: "Checking for an existing organization" })
  const existing = await findOrganizationByIdentifier(identity.taxId)

  onEvent({ step: "organization", label: existing ? "Linking organization" : "Creating organization" })
  const { orgId, invitationPin } = await upsertPartnerOrganization(identity, existing?.orgId)

  onEvent({ step: "access", label: "Granting application access" })
  await platformServiceCall("grantAccess", `/api/v2/external-application/${APP_ID}/allowed-organizations`, {
    method: "PUT",
    body: JSON.stringify({ organizationIdsToAdd: [orgId], organizationIdsToRemove: [] }),
  })

  onEvent({ step: "contact", label: "Saving contact point" })
  const contactPointId = await findOrCreateContactPoint(orgId, contactValue)

  onEvent({ step: "link", label: "Preparing invitation link" })
  const { shortUrl } = await generateInviteLink(orgId)

  onEvent({ step: "send", label: "Sending invitation" })
  await sendInvite(orgId, contactPointId, invitationPin) // PIN travels here, not in the return value

  return { orgId, registrationLink: shortUrl, reusedExistingOrg: Boolean(existing) }
}
```

```ts
// Prefer 1health's own mirror for the identifier lookup — see "Primary vs fallback" above.
async function lookupViaOnehealthMirror(searchText: string, entityTypeCode: 1 | 2 = 2) {
  const res = await callApi<{ data: Array<{ id: number; npi: string; providerOrganizationName?: string }> }>(
    "npi/lookup",
    `/api/v2/public/npi/list?entityTypeCode=${entityTypeCode}&searchText=${encodeURIComponent(searchText)}&page=0&limit=8`,
  )
  // Persist `.id` (the platform-native id), never `.npi` (the 10-digit number), as npiId/organizationNpiId.
  return res.success ? res.data!.data : []
}
```

## Gotchas

- **This can only run server-side, unauthenticated, under a privileged service credential** — there
  is no user token yet. Treat the whole route as a guardrailed exception: rate-limit it hard, and
  re-validate every input server-side even though the client already checked. See
  [split-identity-service-key.md](split-identity-service-key.md).
- **A verified contact channel proves control of that channel, not identity.** Texting a code to a
  phone number the caller typed confirms they hold that handset — not that they are the professional
  named on the identifier. Decide deliberately whether/how to cross-check against the registry's own
  contact info; nothing here blocks a mismatch by default.
- **The PIN must never appear in a response to the browser.** Its only value is that it traveled
  out-of-band; returning it in JSON defeats the entire verification.
- **Granting application access can 403 even for a privileged key** — it can require an admin user
  of the app's *own* tenant. Make it best-effort and surface a manual follow-up rather than failing
  registration outright.
- **A fuzzy org search can resolve to a neighbor.** Always re-verify the exact identifier field on
  a candidate before treating it as "the same org."
- **`organization/list` requires `claimFilter` on every call** — there's no unfiltered default; see
  [partner-org-typeahead.md](partner-org-typeahead.md).
- **1health's NPI mirror's `entityTypeCode`** distinguishes individual (1) vs organization (2)
  records — the wrong value returns an empty list, not an error. Persist `.id`, not `.npi` — both
  are numeric and easy to swap.

## Related

- [partner-invitation-and-pin.md](partner-invitation-and-pin.md), [grant-app-access.md](grant-app-access.md), [deep-link-invite-url.md](deep-link-invite-url.md), [look-then-create.md](look-then-create.md), [ndjson-progress-streaming.md](ndjson-progress-streaming.md) — the sub-mechanics this recipe orchestrates.
- [partner-org-typeahead.md](partner-org-typeahead.md) — the same `organization/list` +
  `claimFilter` search, used interactively instead of server-side.
- [org-claim-status-lookup.md](org-claim-status-lookup.md) — check whether an org from this flow has since been claimed.
- [split-identity-service-key.md](split-identity-service-key.md), [server-side-authorization.md](server-side-authorization.md) — the privileged-credential architecture this flow requires.
- [public-reference-api-proxy.md](public-reference-api-proxy.md) — proxying the external identity registry itself.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md), [setup/auth-and-launch.md](../setup/auth-and-launch.md).
