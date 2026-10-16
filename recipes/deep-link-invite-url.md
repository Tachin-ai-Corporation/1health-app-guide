# Deep-link invite URL

**Use when:** you need a short, brand-able URL that carries an invitation (or similar) target —
e.g. a link opened from SMS/email that lands a partner organization on a themed registration page
with a PIN pre-filled. Also the clean way to **resend** an invitation.
**Routes:** `POST /api/v2/url-mapping/generate` (not yet in the published docs)
**Reference code:** [`lib/onehealth/url-mapping.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-med-adherence-bcbsm/blob/main/lib/onehealth/url-mapping.ts#L108) · [`lib/expertdx/registration.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/lib/expertdx/registration.ts#L532)
**Seen in:** med-adherence, expertdx, pcp-tcm

> **⚠ Not yet in 1health's published API docs:** `POST /api/v2/url-mapping/generate`. 1health supports it for third-party apps, but agents.1health.io has no page for it yet — the shape shown here comes from working apps; the response shape was verified on demo 2026-10-15. Test it against demo before you rely on it.

## Pattern

1. POST `url-mapping/generate` with a `type` query parameter naming what kind of deep link you want
   (e.g. `"Invite Organization"`) and, in the body, the `partnerOrganizationId` of the organization
   you invited — see [partner-invitation-and-pin.md](partner-invitation-and-pin.md).
2. Pass app-open and branding hints through `additionalQueryParams` (e.g. `{ openApp: <appId> }`) —
   these ride into the short link's *destination*, and are your only lever over how the landing
   page looks and behaves.
3. Read the **single object** the call returns: `{ id, shortUrl, hash, invitationPin }`. Older apps
   saw an array, so accept both (`Array.isArray(body) ? body[0] : body`). `shortUrl` looks like
   `https://go.demo.1health.io/<7 chars>`.
4. Take the PIN from `invitationPin.value` while `invitationPin.isUsed` is `false`. `invitationPin`
   is an object, `{ id, value, isUsed }`, holding the invitation's **current** PIN — not a string.
   Fall back to a string `invitationPin` or `pin` for older shapes. **Never** read a PIN out of the
   short link's slug or its `hash`.
5. If the destination page should auto-fill a PIN, append it explicitly as a query string on top of
   the `shortUrl` (e.g. `?pin=…&invitationPin=…`) — the generator does not always embed it for you.
6. **To resend an invitation, call generate again.** You get a fresh short link plus the
   invitation's existing, still-unused PIN, without calling the partner-invitation upsert again.
7. Treat a "target not found" error as recoverable, not fatal: the underlying invitation may have
   been reset or rejected. Resolve that (see partner-invitation-and-pin.md) and retry, rather than
   surfacing a raw platform error to the user.

## Minimal example

```ts
interface InvitationPin { id: number; value: string; isUsed: boolean }
interface UrlMapping {
  id?: number
  shortUrl?: string
  hash?: string                          // part of the short link — never a PIN
  invitationPin?: InvitationPin | string // an object on demo (2026-10-15); a string in older apps
  pin?: string                           // older apps
}

/** The invitation's current PIN, or null when it's already used or absent. */
function currentPin(mapping: UrlMapping): string | null {
  const p = mapping.invitationPin
  if (p && typeof p === "object") return p.isUsed ? null : p.value
  return p ?? mapping.pin ?? null
}

/** Mint a short invite link for a partner org — call it again to resend the invitation. */
async function generateInviteLink(partnerOrgId: number, appId: string, extraParams: Record<string, string> = {}) {
  const res = await callApi<UrlMapping | UrlMapping[]>(
    "invite/generate-link",
    `/api/v2/url-mapping/generate?type=${encodeURIComponent("Invite Organization")}`,
    {
      method: "POST",
      body: JSON.stringify({
        partnerOrganizationId: partnerOrgId,
        additionalQueryParams: { openApp: appId, ...extraParams },
      }),
    },
  )

  const body = res.success ? res.data : undefined
  const mapping = Array.isArray(body) ? body[0] : body // one object today; older apps saw an array
  if (!mapping?.shortUrl) throw new Error(res.error ?? "Could not generate the invitation link")

  const pin = currentPin(mapping)
  const url = pin && !/[?&]pin=/.test(mapping.shortUrl)
    ? `${mapping.shortUrl}?pin=${pin}&invitationPin=${pin}`
    : mapping.shortUrl
  return { shortUrl: mapping.shortUrl, url, pin } // url = shortUrl with the PIN appended, when there is one
}

// e.g. generateInviteLink(partnerOrgId, APP_ID, { source: "sms", brandingId })
```

## Gotchas

- **The response is one object, not an array** (verified on demo 2026-10-15). Code that reads
  `[0].shortUrl` gets `undefined` and no link. Accept both forms.
- **`invitationPin` is an object, not a string** — read `invitationPin.value`, and only while
  `invitationPin.isUsed` is `false`; a used PIN is spent. Stringifying the object gives
  `"[object Object]"`, so a "looks like a 6-digit PIN" check silently finds nothing.
- **Neither the short link's slug nor `hash` is a PIN** — pull the PIN only from a named field in the
  response body.
- **`additionalQueryParams` shape is mapping-`type`-specific** — verify what actually reaches the
  landing page for your `type`; it isn't documented uniformly across mapping types.
- **Regenerating a link for the same target is the resend** — it's idempotent: each call returns a
  fresh `shortUrl` with the invitation's current unused PIN, so repeat it freely instead of
  re-running the partner-invitation upsert.
- A "not found" error on generation often means the underlying invitation/partnership needs
  resetting first, not that the whole flow failed — see
  [partner-invitation-and-pin.md](partner-invitation-and-pin.md).

## Related

- [partner-invitation-and-pin.md](partner-invitation-and-pin.md), [self-service-org-onboarding-by-npi.md](self-service-org-onboarding-by-npi.md), [ndjson-progress-streaming.md](ndjson-progress-streaming.md)
