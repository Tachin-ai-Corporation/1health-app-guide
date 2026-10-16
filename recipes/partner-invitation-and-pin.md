# Partner invitation + PIN

**Use when:** you need to invite an organization into a partnership with your tenant and obtain a
shareable registration PIN — including recovering an invitation that was previously rejected.
**Routes:** `POST /api/v2/organization/partner/invitation` → [agents.md](https://agents.1health.io/public/prod/api/v2/organization/partner/invitation/agents.md) · `POST /api/v2/organization/partnership/request` → [agents.md](https://agents.1health.io/public/prod/api/v2/organization/partnership/request/agents.md) · `PUT /api/v2/organization/partnership/{orgId}/status` → [agents.md](https://agents.1health.io/public/prod/api/v2/organization/partnership/_orgId_/status/agents.md) · `POST /api/v3/otp/verify-code` → [agents.md](https://agents.1health.io/public/prod/api/v3/otp/verify-code/agents.md)
**Reference code:** none public — see the Minimal example.
**Seen in:** A medication-adherence app; the same call opens step 3 of [self-service-org-onboarding-by-npi.md](self-service-org-onboarding-by-npi.md) (a transitional-care app, a specialist-consult ordering app)

## Pattern

1. POST the partner invitation with **one of two body shapes** — the platform documents this route
   as an upsert. Link an existing organization by id when you already resolved one (see
   [partner-org-typeahead.md](partner-org-typeahead.md)); send full organization details instead
   (name, address, tax id, CLIA, NPI) when none exists yet, and the platform mints a new org shell
   in the same call — see [self-service-org-onboarding-by-npi.md](self-service-org-onboarding-by-npi.md).
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
5. Before final submission, you can validate a PIN the user just typed **without spending it**:
   `POST /api/v3/otp/verify-code?type=Partnership Invitation` with `{ orgUuid, code }` returns 200
   (currently valid) or 400 (invalid) and never consumes the code. The PIN is only actually consumed
   when it's presented to complete registration or association — a successful check here is not the
   same as redemption.
6. If you're authoring a workflow template rather than calling the API directly: the platform offers
   two coexisting step kinds for "assign or invite a partner organization" inside a journey. Default
   new templates to the newer one (a fuller, multi-channel invitation config) — both are presumed to
   drive the same underlying invitation mechanics documented here.

## Primary vs fallback

- **Primary — `POST /api/v2/organization/partner/invitation`:** the upsert endpoint — use it
  whenever you don't yet know for certain the target organization exists; it links if you supply a
  matching org id, or mints a new shell if you instead supply full organization details.
- **Fallback — `POST /api/v2/organization/partnership/request`:** use when the org is already
  known — you resolved its id from a typeahead (see [partner-org-typeahead.md](partner-org-typeahead.md))
  or the partner handed you its own shared authorization code. Pass `identifier=organizationId` or
  `identifier=authorizationCode` as a query parameter to say which body field to read.

## Minimal example

```ts
import { callApi, callApiRaw } from "@/lib/api"

type InviteOutcome =
  | { status: "invited"; pin: string; partnershipId: number | null }
  | { status: "already-partnered" } // 409 — get the current PIN from deep-link-invite-url.md if you need it

// callApiRaw, not callApi: this flow needs the status code (409 = success) and the error text
// (to spot a Rejected partnership), and callApi's error string carries neither.
async function postInvitation(body: object): Promise<{ status: number; text: string }> {
  const res = await callApiRaw("/api/v2/organization/partner/invitation", { method: "POST", body: JSON.stringify(body) })
  return { status: res.status, text: await res.text() }
}

async function invitePartner(orgId: number, name: string, email: string): Promise<InviteOutcome> {
  const body = { partnerOrganizationId: orgId, name, email }
  let res = await postInvitation(body)

  // A previously Rejected partnership blocks re-invite: detect it by message text, reset it to
  // Pending (a query parameter), then retry ONCE.
  if (res.status >= 400 && res.status !== 409 && /rejected/i.test(res.text)) {
    await callApi("partner/reset", `/api/v2/organization/partnership/${orgId}/status?partnershipStatus=Pending`, {
      method: "PUT",
    })
    res = await postInvitation(body)
  }

  if (res.status === 409) return { status: "already-partnered" } // success: the partnership exists
  if (res.status !== 200 && res.status !== 201) throw new Error(`Could not invite ${name} (HTTP ${res.status})`)

  // Read the PIN only from a successful body — never from an error body.
  const data = (res.text ? JSON.parse(res.text) : {}) as { invitationPin?: string; pin?: string; id?: number }
  const pin = data.invitationPin ?? data.pin
  if (!pin) throw new Error(`1health did not return a PIN for ${name}`)
  return { status: "invited", pin: String(pin), partnershipId: data.id ?? null }
}

// Upsert branch 2: no existing org id yet — mint one in the same call.
async function inviteNewPartnerOrg(details: {
  name: string
  headquarterAddress?: unknown
  tin?: string
  clia?: string
  npiId?: number
}) {
  const res = await callApi<{ id?: number; invitationPin?: string }>(
    "partner/invite-new",
    "/api/v2/organization/partner/invitation",
    { method: "POST", body: JSON.stringify(details) },
  )
  if (!res.success) throw new Error(`Could not create partner org: ${res.error}`)
  const pin = res.data?.invitationPin
  if (!pin) throw new Error("1health did not return a PIN for the new organization")
  return { pin, organizationId: res.data?.id ?? null }
}

// Non-consuming check: validate a PIN as the user types, without spending it.
async function checkPartnershipPin(orgUuid: string, code: string): Promise<boolean> {
  const res = await callApi(
    "partner/pin-check",
    `/api/v3/otp/verify-code?type=${encodeURIComponent("Partnership Invitation")}`,
    { method: "POST", body: JSON.stringify({ orgUuid, code }) },
  )
  return res.success
}
```

## Gotchas

- **409 is success here, not failure** — it means the invitation/partnership already exists; proceed
  as if the call succeeded.
- **A Rejected partnership silently blocks re-invitation** until you reset its status — and the
  target status travels as a query param, which is easy to miss when reading the endpoint casually.
- **Field names for the PIN and the partnership id are not perfectly uniform** — check the documented
  field first, then fall back defensively; never guess a value out of an unrelated field (a hash, a
  URL slug) just because it happens to look similar. A second named source of the **current** PIN
  is the deep-link generator's response: `invitationPin` there is an object, `{ id, value, isUsed }`
  (verified on demo 2026-10-15). Calling it again resends the invitation with a fresh link and the
  existing unused PIN, with no second upsert — see [deep-link-invite-url.md](deep-link-invite-url.md).
- **Never surface the PIN anywhere client-visible** (logs, error toasts) before it has actually been
  delivered out-of-band — see [deep-link-invite-url.md](deep-link-invite-url.md).
- **Checking a PIN and consuming it are different calls** — `POST /v3/otp/verify-code` only
  validates; redemption happens as a side effect of completing registration/association, never here.
- **The mint-new-org branch's field set is completely different from the link-existing branch** —
  don't merge them into one shared request body; send exactly the fields for the branch you're using.

## Related

- [self-service-org-onboarding-by-npi.md](self-service-org-onboarding-by-npi.md), [grant-app-access.md](grant-app-access.md), [deep-link-invite-url.md](deep-link-invite-url.md), [org-claim-status-lookup.md](org-claim-status-lookup.md)
- [share-with-partner-org.md](share-with-partner-org.md), [partner-org-typeahead.md](partner-org-typeahead.md) — related partner-organization mechanics.
- [partnership-relationship-types.md](partnership-relationship-types.md) — the relationship this
  invitation creates. [message-a-partner-contact-point.md](message-a-partner-contact-point.md) —
  notifying the partner once invited.
