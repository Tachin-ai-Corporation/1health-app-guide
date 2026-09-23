# Custom OTP

> **Advanced / guardrailed pattern.**

**Use when:** the platform's own OTP endpoints (`/api/v3/otp/*`) reject your app's credentials — measured 403 on both a user token and a service key — but you still need a short-code verification step, e.g. proving a caller controls a phone number before texting a session-bearing link to it.
**Routes:** `POST /api/v2/twilio/send` (delivery — see [native-email-and-sms.md](native-email-and-sms.md)) · `POST /api/v2/health/contact-point` · `POST /api/v2/data/custom-data/bulk` — the OTP mint/verify step itself is **not** a 1health call (see Gotchas); confirm the current state of `/api/v3/otp/*` via the [manifest](https://agents.1health.io/public/prod/api/manifest.md) before assuming it's unusable for you too.
**Reference code:** [`lib/mobile/verify.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/lib/mobile/verify.ts)
**Seen in:** expertdx

## Pattern

1. Generate your own short numeric code server-side — don't reach for this until you've confirmed platform OTP actually refuses your credential.
2. Seal the expected code, target phone, and expiry into a short-TTL **httpOnly** cookie. Never hold verification state in server memory (doesn't survive serverless cold starts or multiple instances) and never trust a client-echoed code.
3. Deliver the code via `/api/v2/twilio/send` on the caller's own token, with the exact minimal DTO.
4. On a matching submit: burn the sealed cookie (single use), create the number as a real contact point, and cache a `{contactPointId, last4, verifiedAt}` marker in the user's own `Person` appData — later sends can then skip OTP for an already-verified number.
5. Fall back gracefully: if the appData cache read is ever unavailable, re-derive "already verified" from the live contact-point list rather than forcing a needless re-verification.

## Primary vs fallback

- **Primary — the public, PKCE-bound OTP** (`POST /api/v3/public/otp/send` + `/verify` — see
  [verify-a-contact-channel.md](verify-a-contact-channel.md)): works unauthenticated, so reach for
  it first whenever there's **no session yet**. Try this before assuming you need a self-rolled OTP.
- **Fallback — this recipe's self-rolled OTP:** for an **already-authenticated** user verifying a
  new contact point, where the platform's *authenticated* OTP endpoints (`/api/v3/otp/*`) refuse
  your app's credential. Don't reach for this until you've confirmed that's actually true for you.

## Minimal example

```ts
import { authFetch, getOneHealthBaseUrl } from "@/lib/auth-client"

// 1. Mint a code server-side, seal it (+ phone, expiry) into an httpOnly cookie,
//    then deliver it — the code itself never touches 1health.
async function sendVerificationCode(phoneE164: string, code: string): Promise<boolean> {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/v2/twilio/send`, {
    method: "POST",
    body: JSON.stringify({ toPhoneNumber: phoneE164, text: `Your code is ${code}. Expires in 10 minutes.` }),
  })
  return response.ok
}

// 2. On a correct submit against the sealed cookie: create the contact point,
//    then cache a verified marker under the user's own appData (RMW — see
//    read-write-custom-data.md).
async function recordVerifiedMobile(personId: number, phoneE164: string) {
  const baseUrl = getOneHealthBaseUrl()
  await authFetch(`${baseUrl}/api/v2/health/contact-point`, {
    method: "POST",
    body: JSON.stringify({
      contactPointsToAdd: [{ label: "Personal", type: "Mobile", value: phoneE164, phoneNumberRegion: "us" }],
    }),
  })
  // ...then read current appData and APPEND { mobile: { phoneE164, verifiedAt: Date.now() } }.
}
```

## Gotchas

- This exists **only** because platform OTP refused every credential this app held — verify that's actually true for you before copying it; it's a fallback, not a default.
- Code + expiry must live in a sealed httpOnly cookie, never server memory and never a client-supplied value — a forgeable "verified" persistently hijacks every future send to that identity.
- A verified number is trusted and **reused** — all minting and checking stays server-side, on every path, with no exceptions for convenience.
- Cache "already verified" in the user's own `Person` appData, but fall back to the live contact-point list if that read fails — don't force re-verification over a cache hiccup.

## Related

- [verify-a-contact-channel.md](verify-a-contact-channel.md) — choosing the right verification
  mechanism, including the public OTP this recipe falls back from.
- [native-email-and-sms.md](native-email-and-sms.md) — the delivery channel this borrows.
- [read-write-custom-data.md](read-write-custom-data.md) — the appData caching mechanics.
- [baa-status-split-identity.md](baa-status-split-identity.md) — another guardrailed pattern from the same app.
