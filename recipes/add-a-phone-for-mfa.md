# Add a phone a user can get sign-in codes on (MFA)

**Use when:** a signed-in user should be able to receive 1health sign-in (MFA) codes by text, and
needs to add a mobile number to their own record from inside your app. It applies to any role whose
user may edit their own contact points.
**Routes:** `GET /api/v2/user/myself` → [agents.md](https://agents.1health.io/public/prod/api/v2/user/myself/agents.md) (status line) · `GET /api/v2/user/contact-point/list?type=Mobile` → [agents.md](https://agents.1health.io/public/prod/api/v2/user/contact-point/list/agents.md) · `POST /api/v2/health/contact-point` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/contact-point/agents.md) (add / remove) · `POST /api/v2/health/contact-point/verify` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/contact-point/verify/agents.md) (1health texts its confirmation link) · `PUT /api/v2/public/contact-point/verify?key=…` → [agents.md](https://agents.1health.io/public/prod/api/v2/public/contact-point/verify/agents.md) (what that link calls — not your app) · context only: `GET /api/v2/mfa/config` → [agents.md](https://agents.1health.io/public/prod/api/v2/mfa/config/agents.md) · `POST /api/v2/mfa/send-code` → [agents.md](https://agents.1health.io/public/prod/api/v2/mfa/send-code/agents.md)
**Reference code:** none public — see the Minimal example.
**Seen in:** A specialist-consult ordering app. Verified end to end on a production tenant on
2026-10-22: a number was added, confirmed through 1health's text link, then used for an MFA code. On
demo (2026-10-28) the read routes and the `mfaEnabled`/`totpEnabled` fields were checked; the
add-and-text steps weren't re-run there, because they text a real phone.

## Pattern

1. **MFA only uses verified numbers.** `/v2/mfa/config` lists only verified contact points, and
   `/v2/mfa/send-code` refuses an unverified one. So the whole job is: add a Mobile contact point to
   the user's own record, then have 1health verify it.
2. **Use the person's own token for every call** — never a service key. It's their record and their
   second factor. Show each number masked to its last four digits.
3. **Show a read-only status line.** `/v2/user/myself` returns `mfaEnabled` and `totpEnabled`; say
   what sign-in does today. This flow doesn't turn MFA on or off.
4. **Add.** Normalize what the user typed, then `POST /v2/health/contact-point` with
   `contactPointsToAdd: [{ label, type: "Mobile", value, phoneNumberRegion }]`.
5. **Confirm.** `POST /v2/health/contact-point/verify` with `{ contactPointIds: [id] }`. 1health
   texts its own link; tapping it calls `PUT /v2/public/contact-point/verify?key=…` and marks the
   number verified on 1health's side. You don't build a landing page.
6. **Watch for the confirmation.** After a text goes out, re-read the mobile list on a timer (e.g.
   every 4 s for up to 10 min) and whenever the tab regains focus. Show "Confirmed" once that
   number's `isVerified` is true.
7. **Remove** with `contactPointsToRemove: [id]`.
8. **Rate-limit the "text me" button per person** (e.g. 1 a minute, 5 an hour), because it texts
   whatever number was typed. Keep the send log in the person's own customData (see
   [fail-closed-dedup-ledger.md](fail-closed-dedup-ledger.md)) and fail closed: if the log can't be
   read, don't send. Check the limit **before** adding the number, so a refused text never leaves a
   number behind with no link sent.

## Primary vs fallback

- **Primary — 1health's text link** (`/v2/health/contact-point/verify`): 1health does the
  confirming, so the MFA channel is exactly as strong as 1health.
- **Not an alternative — setting `isVerified` yourself.** A raw attribute write could flip it, but
  your MFA channel would then be only as strong as your app. Don't.
- **Also not an alternative — proving the phone with your own code.** 1health's authenticated OTP
  routes (`/v3/otp/*`) refuse typical app credentials (see [custom-otp.md](custom-otp.md)). A code
  your app sends proves the phone to your app; it never makes the number an MFA channel.

## Minimal example

```ts
import { callApi, callApiRaw, fetchCustomData, mergeCustomData, appData } from "@/lib/api"
// Every call goes through authFetch: the signed-in person's own token, never a service key.

type Mobile = { id: number; value: string; isVerified: boolean | null }

/** Forgiving US input: "(555) 201-0123", "1-555-201-0123", "+1.555.201.0123" → "+1 555 201 0123". */
export function toUsMobile(typed: string): string | null {
  const digits = typed.replace(/\D/g, "")
  const national = digits.length === 11 && digits.startsWith("1") ? digits.slice(1) : digits
  if (national.length !== 10) return null
  return `+1 ${national.slice(0, 3)} ${national.slice(3, 6)} ${national.slice(6)}`
}

export const maskNumber = (value: string) => `•••• ${value.replace(/\D/g, "").slice(-4)}`

/** POST that keeps 1health's own error text ({ message }) — callApi's error string doesn't carry it. */
async function postOrExplain<T>(path: string, body: unknown): Promise<T> {
  const res = await callApiRaw(path, { method: "POST", body: JSON.stringify(body) })
  const data = await res.json().catch(() => null)
  if (res.status === 403) throw new Error("Your role can't change contact details here.")
  if (!res.ok) throw new Error(data?.message ?? `1health refused the request (HTTP ${res.status}).`)
  return data as T
}

async function listMobiles(): Promise<Mobile[]> {
  const res = await callApi<Mobile[]>("mfa-phone/list", "/api/v2/user/contact-point/list?type=Mobile")
  return res.success && Array.isArray(res.data) ? res.data : []
}

export async function signInStatus(): Promise<string> {
  const me = await callApi<{ mfaEnabled?: boolean; totpEnabled?: boolean }>("mfa-phone/me", "/api/v2/user/myself")
  if (!me.success || !me.data) return "Couldn't read your sign-in settings."
  if (!me.data.mfaEnabled) return "Sign-in doesn't ask for a code right now."
  return me.data.totpEnabled ? "Sign-in asks for a code; an authenticator app is set up." : "Sign-in asks for a code."
}

/** Fail-closed per-person limit, logged in the person's own customData. Call BEFORE adding a number. */
async function reserveText(personId: number, appId: string): Promise<boolean> {
  const read = await fetchCustomData("Person", personId)
  if (!read.success) return false // can't read the log → don't send
  const now = Date.now()
  const recent: number[] = ((read.data!.appData as any)?.[appId]?.mfaTextsAt ?? []).filter((t: number) => now - t < 3_600_000)
  if (recent.filter((t) => now - t < 60_000).length >= 1 || recent.length >= 5) return false
  const saved = await mergeCustomData("Person", personId, appData(appId, { mfaTextsAt: [...recent, now] }))
  return saved.success
}

/** Limit → add → ask 1health to text its link. Returns the new contact point's id. */
export async function addAndConfirm(typed: string, personId: number, appId: string): Promise<number> {
  const value = toUsMobile(typed)
  if (!value) throw new Error("Enter a 10-digit US mobile number.")
  if (!(await reserveText(personId, appId))) throw new Error("Too many texts — try again in a minute.")

  const before = new Set((await listMobiles()).map((m) => m.id))
  const mobile = { type: "Mobile", label: "Personal", value, phoneNumberRegion: "us" }
  await postOrExplain("/api/v2/health/contact-point", { contactPointsToAdd: [mobile] })
  const added = (await listMobiles()).find((m) => !before.has(m.id)) // find it by id, not by the string
  if (!added) throw new Error("The number was saved but couldn't be found again. Refresh and retry.")

  const sent = await postOrExplain<{ success: boolean; contactPointIdsWithSendError?: number[] }>(
    "/api/v2/health/contact-point/verify",
    { contactPointIds: [added.id] },
  )
  if (!sent?.success || sent.contactPointIdsWithSendError?.includes(added.id)) {
    throw new Error("1health couldn't text that number.")
  }
  return added.id
}

export const removeMobile = (id: number) => postOrExplain("/api/v2/health/contact-point", { contactPointsToRemove: [id] })

/** Re-read every 4 s and on tab focus; stop on confirmation or after 10 minutes. Returns a stop(). */
export function watchUntilVerified(id: number, onConfirmed: () => void, everyMs = 4_000, forMs = 600_000) {
  const giveUpAt = Date.now() + forMs
  let done = false
  const stop = () => { done = true; clearInterval(timer); window.removeEventListener("focus", check) }
  async function check() {
    if (done) return
    if (Date.now() > giveUpAt) return stop()
    const mobile = (await listMobiles()).find((m) => m.id === id)
    if (!done && mobile?.isVerified) { stop(); onConfirmed() }
  }
  const timer = setInterval(check, everyMs)
  window.addEventListener("focus", check)
  return stop
}
```

## Gotchas

- **Make the input forgiving.** Accept any punctuation and a leading `1` or `+1`, format as the user
  types, and validate before calling. Send `value` in international form with `phoneNumberRegion`;
  an unformatted 10-digit string a user typed should never fail.
- **Show 1health's own error message** (the `message` in its error body) when the add or the text
  fails, instead of a generic "couldn't text that number." The verify response also names any number
  it couldn't text in `contactPointIdsWithSendError`.
- **Roles.** The contact-point route docs list system roles (`Patient`, `Multi-Tenant Administrator`,
  `System Administrator`). Test the roles your app actually uses on demo, and show a plain message on
  a 403.
- **`mfaEnabled` and `totpEnabled` come back on `/v2/user/myself`** (checked on demo, 2026-10-28)
  even though its published field list doesn't show them — read them defensively.
- **The rate limit guards your button, not the route.** The person's own token can call the verify
  route directly; the limit stops your UI from becoming a way to text arbitrary numbers.
- **Text only verified numbers elsewhere.** Any other feature that texts a user (a "send to phone"
  link, for instance) should trust only `isVerified` mobiles. Removing a number should also clear it
  from anything that cached it.
- **The other verification routes aren't MFA.** The contact-channel routes prove someone controls a
  channel ([verify-a-contact-channel.md](verify-a-contact-channel.md)); this recipe is how a
  verified mobile becomes an MFA channel.

## Related

- [verify-a-contact-channel.md](verify-a-contact-channel.md) — the other verification routes, and
  why they aren't MFA.
- [custom-otp.md](custom-otp.md) — why your own code can't stand in for 1health's verification.
- [native-email-and-sms.md](native-email-and-sms.md) — texting a user, once their mobile is verified.
- [fail-closed-dedup-ledger.md](fail-closed-dedup-ledger.md),
  [read-write-custom-data.md](read-write-custom-data.md) — the fail-closed send log in the person's
  own customData.
- Concepts: [setup/auth-and-launch.md](../setup/auth-and-launch.md)
