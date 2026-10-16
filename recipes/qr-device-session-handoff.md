# QR device-session hand-off

> **Advanced / guardrailed pattern.**

**Use when:** an already-authenticated device needs a second device (typically a phone camera) to act under the **same session** for one short task, with no separate login on the second device and no backend session store of your own.
**Routes:** app-owned hand-off routes; the underlying 1health write is a top-level `POST /api/v2/data/custom-data/bulk` APPEND → [agents.md](https://agents.1health.io/public/prod/api/v2/data/custom-data/bulk/agents.md) (the matching single-instance read is a sibling endpoint — see [manifest.md](https://agents.1health.io/public/prod/api/manifest.md) if you need its exact shape)
**Reference code:** none public — see the Minimal example.
**Seen in:** A transitional-care app, a specialist-consult ordering app

## Pattern

1. Seal (AES-256-GCM) the authenticated device's session into a bundle, with a server-only key derived via HKDF from your own service/secret key, domain-separated (a distinct `info` string) from any other key you derive from that same secret.
2. Mint a random, high-entropy nonce. Write **only** `{ nonce, expiry, used: false }` — never the sealed session — as its own top-level `customData` key on a record both devices can reach, via a top-level `APPEND` so it can't clobber other keys.
3. Put the sealed bundle in the QR link's URL **fragment**, never its path or query — fragments are never sent to any server by the browser, so the credential never touches an access log, a referrer header, or a request trace.
4. The second device posts the fragment + nonce to a redeem endpoint, which: opens the seal first (a foreign/tampered blob fails cleanly here, rather than surfacing as a false "expired") → uses the now-recovered session to verify the nonce against the burn record → writes `used: true` **before** returning anything → only then hands the session to the second device. A concurrent second redemption loses the race to the burn write, not to a check-then-act gap.
5. Give the ticket a short TTL (minutes); a fresh mint overwrites any previous ticket on the same record, so re-displaying the code invalidates the old link.

## Minimal example

```ts
import { randomBytes } from "node:crypto"

const HANDOFF_KEY = "deviceHandoff" // its own top-level customData key, a sibling of appData
const HANDOFF_TTL_MS = 10 * 60_000

// mint — runs on the authenticated device's own server-side session
export async function mintHandoffLink(owner: ServerCaller, recordId: number, session: HandoffSession) {
  const nonce = randomBytes(32).toString("base64url")
  const ticket = { nonce, expiresAt: Date.now() + HANDOFF_TTL_MS, used: false } // never the session itself
  await appendTopLevelKey(owner, recordId, HANDOFF_KEY, ticket) // replaces any older ticket on the record
  const fragment = encryptForLink(session) // AES-256-GCM, HKDF-derived key
  return `${appUrl}/handoff/${recordId}#${fragment}` // fragment — never sent to any server
}

// redeem — server-only; no client session exists yet, so this rebuilds one from the seal
export async function redeemHandoff(recordId: number, nonce: string, fragment: string) {
  const session = decryptFromLink<HandoffSession>(fragment) // null on ANY decrypt failure, never throws
  if (!session) return { ok: false, status: "corrupt" } as const

  const owner = toServerCaller(session) // the RECOVERED session reads its own record
  const ticket = await readTopLevelKey(owner, recordId, HANDOFF_KEY)
  const redeemable = !!ticket && !ticket.used && ticket.nonce === nonce && Date.now() <= ticket.expiresAt
  if (!redeemable) return { ok: false, status: "invalid" } as const

  await appendTopLevelKey(owner, recordId, HANDOFF_KEY, { ...ticket, used: true }) // burn FIRST
  return { ok: true, session } as const
}
```

## Gotchas

- **A privileged service/admin credential usually can't reach this record** (it's typically scoped to your own tenant, not the customer's) — that's why redeem uses the session recovered from the seal to read/write, not a service key.
- **The client's cookie-reading `authFetch` doesn't run in a server route.** Mint and redeem execute server-side, so attach `Authorization: Bearer <token>` directly via a thin server-side caller — still resolve the base URL per call, never hardcode it.
- **Burn the ticket before returning the session**, or two near-simultaneous redemptions can both succeed.
- **Use an authenticated cipher (GCM)** and collapse every decrypt failure into one "corrupt" result — never throw on a tampered blob.
- **This grants a capability, not a login** — anyone holding the un-redeemed link gets the session, so size the TTL to "long enough to glance at a second device," not longer.

## Related

- [provider-minted-magic-link.md](provider-minted-magic-link.md)
- [capability-probe.md](capability-probe.md)
- Concepts: [setup/auth-and-launch.md](../setup/auth-and-launch.md)
