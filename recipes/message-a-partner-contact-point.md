# Message a partner organization's contact point

**Use when:** you need to notify a specific partner organization through one of its own registered
contact points (email/fax/mobile) — not a generic email/SMS send — and, for fax, want to show
exactly what will be sent before it goes out.
**Routes:** `POST /api/v2/organization/partner/{id}/contact-point` → [agents.md](https://agents.1health.io/public/prod/api/v2/organization/partner/_id_/contact-point/agents.md) (create a contact point) · `POST /api/v2/organization/partner/{id}/contact-point/{contactPointId}/preview` → [agents.md](https://agents.1health.io/public/prod/api/v2/organization/partner/_id_/contact-point/_contactPointId_/preview/agents.md) (fax preview, PDF) · `POST /api/v2/organization/partner/{id}/contact-point/{contactPointId}/send` → [agents.md](https://agents.1health.io/public/prod/api/v2/organization/partner/_id_/contact-point/_contactPointId_/send/agents.md) (send)
**Reference code:** none public — see the Minimal example.
**Seen in:** 1health platform usage

## Pattern

1. A partner organization can have several registered contact points (email/fax/mobile) — create or
   look up the specific one you're targeting first. Send and preview are scoped to
   `{partnerId}/{contactPointId}`, not to the organization alone.
2. The notification body is a **union, not one fixed shape**: fax and email want a `subject` plus a
   `bodyMessage` (and optional branding fields); mobile/SMS needs only `bodyMessage`. Build the
   payload from the target contact point's own `type`, not a single shared form.
3. For a **fax** contact point specifically, call **preview** first with the exact payload you intend
   to send — it renders the same document as a PDF so you (or the end user) can confirm it before
   anything actually goes out.
4. Only after confirmation, call **send** with the identical body. There's no token or id from the
   preview you need to carry over — "same payload" is the whole contract between the two calls.
5. Treat delivery as fire-and-forget from the caller's side — the call reports whether the send was
   accepted, not whether or when the partner actually received it.

## Minimal example

```ts
import { callApi } from "@/lib/api"

type PartnerChannel = "Email" | "Fax" | "Mobile"

interface PartnerNotification {
  subject?: string       // required for Email/Fax
  bodyMessage: string    // always required
  brandName?: string
  brandLogoUrl?: string
}

function buildPayload(type: PartnerChannel, body: PartnerNotification) {
  if (type === "Mobile") return { bodyMessage: body.bodyMessage }
  return body // Email/Fax also want `subject` (and optional branding fields)
}

// Register a contact point before you can send/preview to it.
async function createPartnerContactPoint(partnerId: number, type: PartnerChannel, name: string, value: string) {
  const res = await callApi<{ id: number }>(
    "partner/contact-point.create",
    `/api/v2/organization/partner/${partnerId}/contact-point`,
    { method: "POST", body: JSON.stringify({ name, type, value }) },
  )
  if (!res.success) throw new Error(res.error)
  return res.data!.id
}

// Fax only: render the exact PDF that `send` would deliver, before sending it.
async function previewFax(partnerId: number, contactPointId: number, body: PartnerNotification) {
  const res = await callApi<Blob>(
    "partner/contact-point.preview",
    `/api/v2/organization/partner/${partnerId}/contact-point/${contactPointId}/preview`,
    { method: "POST", body: JSON.stringify(body) },
  )
  return res.success ? res.data : null // render or download as a PDF
}

async function sendToPartnerContactPoint(
  partnerId: number,
  contactPointId: number,
  type: PartnerChannel,
  body: PartnerNotification,
) {
  const res = await callApi(
    "partner/contact-point.send",
    `/api/v2/organization/partner/${partnerId}/contact-point/${contactPointId}/send`,
    { method: "POST", body: JSON.stringify(buildPayload(type, body)) },
  )
  if (!res.success) throw new Error(res.error)
}
```

## Gotchas

- The payload shape depends on the target contact point's `type` — build it from that type, not a
  single shared form; a fax/email-shaped body sent to a mobile contact point isn't what the
  endpoint expects.
- Preview is meaningful for **fax** specifically (it renders the generated fax document as a PDF) —
  don't assume it's necessary, or behaves the same way, for email/mobile.
- Preview and send are independent calls sharing one body shape — there's no confirmation token to
  pass from one to the other; just re-send the identical payload once confirmed.
- Registering a new contact point is a separate call from sending to one you already have — resolve
  or create the contact point id first.

## Related

- [partnership-relationship-types.md](partnership-relationship-types.md) — the partner relationship
  this notifies within.
- [partner-invitation-and-pin.md](partner-invitation-and-pin.md) — inviting the partner in the first
  place.
- [native-email-and-sms.md](native-email-and-sms.md) — generic, non-partner-scoped email/SMS
  delivery.
