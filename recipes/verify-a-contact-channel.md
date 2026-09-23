# Verify a contact channel

**Use when:** you need to prove someone actually controls an email, phone, fax number, or
invitation PIN before you trust it — a brand-new contact with no 1health session yet, a channel
being added to an existing account, or a partner org's own invitation PIN.
**Routes:** `POST /api/v3/public/otp/send` → [agents.md](https://agents.1health.io/public/prod/api/v3/public/otp/send/agents.md) + `POST /api/v3/public/otp/verify` → [agents.md](https://agents.1health.io/public/prod/api/v3/public/otp/verify/agents.md) (interactive code) · `POST /api/v2/public/verify-email/{userId}/{identifier}` → [agents.md](https://agents.1health.io/public/prod/api/v2/public/verify-email/agents.md) · `PUT /api/v2/public/contact-point/verify?key={key}` → [agents.md](https://agents.1health.io/public/prod/api/v2/public/contact-point/verify/agents.md) (click-through links) · `POST /api/v3/otp/verify-code?type=Partnership Invitation` → [agents.md](https://agents.1health.io/public/prod/api/v3/otp/verify-code/agents.md) (non-consuming PIN check) · `POST /api/v2/public/health/verify?type=Partner Registration` → [agents.md](https://agents.1health.io/public/prod/api/v2/public/health/verify/agents.md) (fax legitimacy check)
**Reference code:** none public — see the Minimal example
**Seen in:** 1health platform usage

## Pattern

1. **Decide who's present, and when.** Person present right now, typing a code they just
   received, no session yet → interactive OTP. Channel verified asynchronously — they may click a
   link minutes or hours later, possibly from a different device → a click-through link. Need to
   validate a PIN as the user types, without spending a limited-use secret → a non-consuming check.
   Confirming a fax number belongs to who it claims → the fax legitimacy check.
2. For the OTP path, generate a PKCE pair **client-side**: a random `codeVerifier`, and
   `codeChallenge = BASE64URL(SHA-256(codeVerifier))`. Send only the challenge; the verifier never
   leaves the client until you know you'll need it again.
3. Persist the in-flight `requestId` + `codeChallenge` (+ verifier) across a re-render or a
   wizard's back/forward — a remount that loses the verifier makes an otherwise-valid code
   unusable.
4. Verify with the same challenge and the code the user typed. A resend while the cooldown is
   still active comes back `429` with `retryAfterSeconds` and no message field — special-case it
   into a countdown, not a generic error toast.
5. For a click-through link, mint or receive it out of band (email/SMS); the landing page just
   calls the verify endpoint with whatever path/query values the link carries — there's no code for
   the user to type.
6. For a non-consuming check, call it on every keystroke/blur you want to validate against; it
   answers pass/fail only and never spends the underlying PIN — the real submission that the PIN
   belongs to (e.g. completing an invitation) is what consumes it for real.
7. Treat all of these as answering only "does this match." None of them are MFA, and none replace
   your own authorization check once the channel is confirmed.

## Primary vs fallback

- **Primary — interactive OTP** (`/v3/public/otp/send` + `/verify`): the default whenever the
  person is present and there's no session yet. No credential required, and PKCE-bound so only the
  browser that requested the code can redeem it.
- **Fallback — click-through link** (`/v2/public/verify-email/...`, `/v2/public/contact-point/verify`):
  use when verification must survive the person leaving and coming back later, or acting from a
  different device — there's nothing to type, just a link to click.
- **Special case — non-consuming PIN check** (`/v3/otp/verify-code`): reach for this only when you
  need live, as-you-type validation of a PIN without burning it. Your real submission path still
  has to consume the PIN for real.

## Minimal example

```ts
import { authFetch, getOneHealthBaseUrl } from "@/lib/auth-client"

class RetryAfterError extends Error {
  constructor(public retryAfterSeconds: number) { super("OTP send is rate-limited") }
}

async function sha256Base64Url(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input))
  return btoa(String.fromCharCode(...new Uint8Array(digest))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

/** Step 1: send a 6-digit code, PKCE-bound to this browser. Persist all three return values. */
async function sendContactOtp(contact: string) {
  const codeVerifier = crypto.randomUUID() + crypto.randomUUID()
  const codeChallenge = await sha256Base64Url(codeVerifier)
  const baseUrl = getOneHealthBaseUrl()
  const res = await authFetch(`${baseUrl}/api/v3/public/otp/send`, {
    method: "POST",
    body: JSON.stringify({ contact, codeChallenge }),
  })
  if (res.status === 429) throw new RetryAfterError((await res.json()).retryAfterSeconds)
  if (!res.ok) throw new Error(`Could not send a code: ${res.status}`)
  const { requestId } = await res.json()
  return { requestId, codeVerifier, codeChallenge }
}

/** Step 2: verify with the SAME challenge used to send it. */
async function verifyContactOtp(requestId: string, otp: string, codeChallenge: string) {
  const baseUrl = getOneHealthBaseUrl()
  const res = await authFetch(`${baseUrl}/api/v3/public/otp/verify`, {
    method: "POST",
    body: JSON.stringify({ requestId, otp, codeChallenge }),
  })
  if (!res.ok) throw new Error(`Invalid or expired code: ${res.status}`)
  const { verificationToken } = await res.json() // present this to whatever call needed the proof
  return verificationToken as string
}

/** Non-consuming check: validate a PIN as the user types, without spending it. */
async function pinLooksValid(orgUuid: string, code: string): Promise<boolean> {
  const baseUrl = getOneHealthBaseUrl()
  const res = await authFetch(`${baseUrl}/api/v3/otp/verify-code?type=${encodeURIComponent("Partnership Invitation")}`, {
    method: "POST",
    body: JSON.stringify({ orgUuid, code }),
  })
  return res.ok // 200 = still valid and unused; the real invitation flow consumes it for real
}
```

## Gotchas

- **`codeChallenge` binds the OTP session to the browser that requested it** — generate
  `codeVerifier` fresh per send and never reuse one across sessions; `verificationToken` is what
  you carry forward afterward, not the verifier.
- **A resend during the cooldown is `429` with `retryAfterSeconds` and no message field** — a
  generic error handler renders a useless toast; special-case it into a countdown.
- **The email-verify link takes `{userId}/{identifier}` as two path segments**, not one opaque
  token — build the link with both or it's malformed, not just wrong.
- **The non-consuming check and the fax check both answer a bare yes/no** — don't let a catch-all
  error handler leak extra backend text past that boolean.
- **None of this is MFA.** These endpoints prove someone controls a channel; they don't gate a
  second factor on an existing login.

## Related

- [custom-otp.md](custom-otp.md) — the fallback for an already-authenticated user whose credential
  the *authenticated* OTP endpoints refuse.
- [add-users-to-a-tenant.md](add-users-to-a-tenant.md), [partner-invitation-and-pin.md](partner-invitation-and-pin.md) —
  flows that actually consume a PIN this recipe's non-consuming check only previews.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
