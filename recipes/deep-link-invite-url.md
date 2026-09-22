# Deep-link invite URL

**Use when:** you need a short, brand-able URL that carries an invitation (or similar) target —
e.g. a link opened from SMS/email that lands a partner organization on a themed registration page
with a PIN pre-filled.
**Routes:** `POST /api/v2/url-mapping/generate` → [route docs](https://agents.1health.io/public/prod/api/manifest.md)
**Reference code:** [`lib/onehealth/url-mapping.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-med-adherence-bcbsm/blob/main/lib/onehealth/url-mapping.ts#L108) · [`lib/expertdx/registration.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/lib/expertdx/registration.ts#L532)
**Seen in:** med-adherence, expertdx, pcp-tcm

## Pattern

1. POST `url-mapping/generate` with a `type` naming what kind of deep link you want (e.g.
   `"Invite Organization"`) and the target id it's tied to — typically the partner invitation from
   [partner-invitation-and-pin.md](partner-invitation-and-pin.md).
2. Pass branding/app-open hints through `additionalQueryParams` — these ride into the short link's
   *destination*, and are your only lever over how the landing page looks and behaves.
3. Parse the response array's `[0].shortUrl`. Extract any PIN only from named fields (`pin`,
   `invitationPin`, `code`) — **never** from the short link's own hash-like slug.
4. If the destination page should auto-fill a PIN, append it explicitly as a query string on top of
   the `shortUrl` (e.g. `?pin=…&invitationPin=…`) — the generator does not always embed it for you.
5. Treat a "target not found" error as recoverable, not fatal: the underlying invitation may have
   been reset or rejected. Resolve that (see partner-invitation-and-pin.md) and retry, rather than
   surfacing a raw platform error to the user.

## Minimal example

```ts
async function generateInviteLink(partnerOrgId: number, brandingId: string) {
  const res = await callApi<Array<{ shortUrl?: string; pin?: string; invitationPin?: string }>>(
    "invite/generate-link",
    `/api/v2/url-mapping/generate?type=${encodeURIComponent("Invite Organization")}`,
    {
      method: "POST",
      body: JSON.stringify({
        partnerOrganizationId: partnerOrgId,
        additionalQueryParams: { openApp: "YourApp", source: "sms", brandingId },
      }),
    },
  )

  const row = res.success ? res.data?.[0] : undefined
  if (!row?.shortUrl) throw new Error(res.error ?? "Could not generate the invitation link")

  const pin = row.pin ?? row.invitationPin
  const url = pin && !/[?&]pin=/.test(row.shortUrl) ? `${row.shortUrl}?pin=${pin}&invitationPin=${pin}` : row.shortUrl
  return { url, pin: pin ?? null }
}
```

## Gotchas

- **The short link's slug is not a PIN** — pull the PIN only from a named field in the response body.
- **`additionalQueryParams` shape is mapping-`type`-specific** — verify what actually reaches the
  landing page for your `type`; it isn't documented uniformly across mapping types.
- **Regenerating a link for the same target is normal** — treat it as an idempotent "resend," not a
  one-shot operation you have to guard against repeating.
- A "not found" error on generation often means the underlying invitation/partnership needs
  resetting first, not that the whole flow failed — see
  [partner-invitation-and-pin.md](partner-invitation-and-pin.md).

## Related

- [partner-invitation-and-pin.md](partner-invitation-and-pin.md), [self-service-org-onboarding-by-npi.md](self-service-org-onboarding-by-npi.md), [ndjson-progress-streaming.md](ndjson-progress-streaming.md)
