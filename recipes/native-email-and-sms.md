# Native email and SMS

**Use when:** you need to send a transactional email or SMS from the app — notifications, confirmations, a staff-alert widget — without standing up a third-party mailer.
**Routes:** `POST /api/v2/email/send` → [agents.md](https://agents.1health.io/public/prod/api/v2/email/send/agents.md) · `POST /api/v2/twilio/send` → [agents.md](https://agents.1health.io/public/prod/api/v2/twilio/send/agents.md)
**Reference code:** [`app/api/feedback/route.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/app/api/feedback/route.ts) (email) · [`lib/mobile/verify.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/lib/mobile/verify.ts) (SMS)
**Seen in:** pcp-tcm, expertdx (med-adherence uses SendGrid instead — see [anti-patterns.md](../setup/anti-patterns.md))

## Pattern

1. 1health is itself a comms provider — send transactional email/SMS through its own endpoints on the **caller's own bearer token**, instead of reaching for a third-party mailer as your default.
2. Send **exactly** the documented fields for each endpoint and nothing more. Both endpoints have been driven into a failing serialization path (an HTTP 500, not a clean 400) in production by one extra or guessed field.
3. Resolve *who* the message is from/about (name, org) server-side from the session's own token — never trust caller-supplied identity fields for anything that ends up in a message body.
4. Treat a send failure as a real, visible outcome — a 401/403 means this token specifically can't use the endpoint, which is worth distinguishing from a generic failure so it actually gets fixed.
5. If you proxy the send through your own server route, gate it behind your own session check — it's a channel from a signed-in user to a fixed purpose/recipient, not an open relay.

## Minimal example

```ts
// Server route: relay a signed-in user's message as email.
// `getCaller()` is your own session helper — resolves the request's cookie to
// { accessToken, baseUrl }; it is not a 1health call.
export async function POST(request: Request) {
  const caller = await getCaller()
  if (!caller) return Response.json({ error: "Not signed in." }, { status: 401 })

  const { message } = await request.json()

  const response = await fetch(`${caller.baseUrl}/api/v2/email/send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${caller.accessToken}`, "Content-Type": "application/json" },
    // EXACTLY these three fields — an extra field has 500'd this endpoint in production.
    body: JSON.stringify({
      subject: "App notification",
      text: message,
      userEmail: "recipient@example.com", // the RECIPIENT, not the sender
    }),
  })

  if (!response.ok) return Response.json({ error: "Send failed." }, { status: 502 })
  return Response.json({ ok: true })
}
```

```ts
import { authFetch, getOneHealthBaseUrl } from "@/lib/auth-client"

// SMS, same minimal-DTO discipline, on the caller's own token.
async function sendSms(toPhoneE164: string, text: string): Promise<boolean> {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/v2/twilio/send`, {
    method: "POST",
    body: JSON.stringify({ toPhoneNumber: toPhoneE164, text }),
  })
  return response.ok
}
```

## Gotchas

- **Minimal-DTO discipline is not optional** — extra or guessed fields have driven both endpoints into a failing serialization path (HTTP 500) in production. Send only the documented fields, nothing more.
- `userEmail` on the email endpoint is the **recipient** — confirm field semantics against the live doc rather than assuming from the name.
- These run on the **caller's own bearer token**; a token that simply can't send returns 401/403, a meaningfully different failure than a bad payload.
- A server route that proxies a send (to keep the token server-side, or to inject session-resolved identity into the body) legitimately uses a plain `fetch` with a manually-attached Bearer header, read from an httpOnly cookie — `authFetch`'s browser-side refresh logic isn't the point there.
- Prefer these over a third-party mailer as your default — see [anti-patterns.md](../setup/anti-patterns.md); reach for a third party only for a concrete gap these two don't cover.

## Related

- [custom-otp.md](custom-otp.md) — builds SMS delivery into a self-rolled verification flow when platform OTP itself isn't usable.
- [anti-patterns.md](../setup/anti-patterns.md) — the SendGrid deviation this recipe replaces.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md).
