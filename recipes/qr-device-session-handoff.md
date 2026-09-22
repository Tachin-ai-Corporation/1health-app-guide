# QR device-session hand-off

> **Advanced / guardrailed pattern.**

**Use when:** an already-authenticated device needs a second device (typically a phone camera) to act under the **same session** for one short task, with no separate login on the second device and no backend session store of your own.
**Routes:** app-owned hand-off routes; the underlying 1health write is a top-level `POST /api/v2/data/custom-data/bulk` APPEND → [agents.md](https://agents.1health.io/public/prod/api/v2/data/custom-data/bulk/agents.md) (the matching single-instance read is a sibling endpoint — see [manifest.md](https://agents.1health.io/public/prod/api/manifest.md) if you need its exact shape)
**Reference code:** [`lib/mobile/ticket.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/mobile/ticket.ts) + [`crypto.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/mobile/crypto.ts) · ExpertDx variant: [`lib/mobile/ticket.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/lib/mobile/ticket.ts) + [`crypto.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/lib/mobile/crypto.ts)
**Seen in:** pcp-tcm, expertdx

## Pattern

1. Seal (AES-256-GCM) the authenticated device's session into a bundle, with a server-only key derived via HKDF from your own service/secret key, domain-separated (a distinct `info` string) from any other key you derive from that same secret.
2. Mint a random, high-entropy nonce. Write **only** `{ nonce, expiry, used: false }` — never the sealed session — as its own top-level `customData` key on a record both devices can reach, via a top-level `APPEND` so it can't clobber other keys.
3. Put the sealed bundle in the QR link's URL **fragment**, never its path or query — fragments are never sent to any server by the browser, so the credential never touches an access log, a referrer header, or a request trace.
4. The second device posts the fragment + nonce to a redeem endpoint, which: opens the seal first (a foreign/tampered blob fails cleanly here, rather than surfacing as a false "expired") → uses the now-recovered session to verify the nonce against the burn record → writes `used: true` **before** returning anything → only then hands the session to the second device. A concurrent second redemption loses the race to the burn write, not to a check-then-act gap.
5. Give the ticket a short TTL (minutes); a fresh mint overwrites any previous ticket on the same record, so re-displaying the code invalidates the old link.

## Minimal example

```ts
// mint — runs on the authenticated device's own server-side session
const nonce = randomBytes(32).toString("base64url")
await appendTopLevelKey(caller, recordId, "captureTicket", { nonce, exp: Date.now() + 10 * 60_000, used: false })
const sealed = sealJson(sessionBundle)                       // AES-256-GCM, HKDF-derived key
const qrUrl = `${appUrl}/capture/${recordId}#${sealed}`      // fragment — never sent to any server

// redeem — server-only; no client session exists yet, so this rebuilds one from the seal
export async function redeemTicket(recordId: number, nonce: string, sealed: string) {
  const bundle = openJson<SessionBundle>(sealed)
  if (!bundle) return { ok: false, status: "corrupt" } as const
  const caller = callerFromBundle(bundle)                    // the RECOVERED session reads its own record
  const ticket = await readTopLevelKey(caller, recordId, "captureTicket")
  if (!ticket || ticket.used || Date.now() > ticket.exp || ticket.nonce !== nonce) {
    return { ok: false, status: "invalid" } as const
  }
  await appendTopLevelKey(caller, recordId, "captureTicket", { ...ticket, used: true })  // burn FIRST
  return { ok: true, bundle } as const
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
