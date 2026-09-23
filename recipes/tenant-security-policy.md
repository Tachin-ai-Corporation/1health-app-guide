# Set a tenant's lockout & session policy

> **Advanced / guardrailed pattern.**

**Use when:** an admin needs to read or change how aggressively a tenant locks out failed logins,
or how long a session stays valid, for the whole tenant.
**Routes:** `GET /api/v2/tenant/security-configuration?tag=user-failed-password-attempts&tag=user-session` (not yet in the published docs) · `PUT /api/v2/tenant/security-configuration` (not yet in the published docs)

> **⚠ Not yet in 1health's published API docs:** `GET`/`PUT /api/v2/tenant/security-configuration`. 1health supports it for third-party apps, but agents.1health.io has no page for it yet — the shape shown here comes from working apps. Test it against demo before you rely on it.

**Reference code:** none public — see the Minimal example
**Seen in:** 1health platform usage

## Pattern

1. Read both settings in **one** call by repeating the `tag` query parameter — send it as two
   separate `tag=` pairs, not a single array-style value.
2. The response gives session length in **seconds**; a settings UI that shows/edits **minutes**
   must convert both ways — a raw passthrough is off by 60x.
3. Before writing a lockout threshold of `0` (which disables lockout entirely, not "softly"),
   **get explicit confirmation** naming the consequence — this is a real security-relevant change,
   not a routine settings tweak.
4. PUT only the fields you're changing, as a partial update over the same shape the GET returns.

## Minimal example

```ts
import { authFetch, getOneHealthBaseUrl } from "@/lib/auth-client"

interface SecurityPolicy {
  userBearerTokenValidity: number // seconds, on the wire
  numberOfAllowedFailedPasswordAttemptsBeforeUserLockOut: number
  counterTimeIntervalOfAllowedFailedPasswordAttemptsBeforeUserLockOut: number // minutes
}

async function getSecurityPolicy(): Promise<SecurityPolicy> {
  const baseUrl = getOneHealthBaseUrl()
  const qs = "tag=user-failed-password-attempts&tag=user-session" // repeated, not an array param
  const res = await authFetch(`${baseUrl}/api/v2/tenant/security-configuration?${qs}`)
  if (!res.ok) throw new Error(`Could not read security policy: ${res.status}`)
  return res.json()
}

// Caller must gate a `numberOfAllowedFailedPasswordAttemptsBeforeUserLockOut: 0` write behind an
// explicit admin confirmation first — that value disables lockout entirely, not softly.
async function setSecurityPolicy(partial: Partial<SecurityPolicy>) {
  const baseUrl = getOneHealthBaseUrl()
  const res = await authFetch(`${baseUrl}/api/v2/tenant/security-configuration`, {
    method: "PUT",
    body: JSON.stringify(partial),
  })
  if (!res.ok) throw new Error(`Could not update security policy: ${res.status}`)
}
```

## Gotchas

- **Session length is seconds on the wire, minutes in any sane UI** — convert explicitly in both
  directions.
- **A lockout threshold of `0` is a real "disable lockout" change**, not a no-op — gate it behind
  an explicit confirmation naming the consequence.
- **This route isn't in the published docs yet** — confirm the exact field names against demo
  before shipping a settings screen around them.

## Related

- [add-users-to-a-tenant.md](add-users-to-a-tenant.md) — the membership flows this policy governs.
- [scoped-api-key-with-role.md](scoped-api-key-with-role.md) — another privileged, confirm-before-write setting.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
