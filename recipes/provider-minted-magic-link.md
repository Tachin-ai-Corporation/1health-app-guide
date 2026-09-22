# Provider-minted magic link

> **Advanced / guardrailed pattern.**

**Use when:** an authenticated user needs to hand a **reusable, long-lived** link to someone with no account (a patient, an external contact) that identifies one record, without minting that person a session.
**Routes:** app-owned link-minting route; the underlying 1health write is a top-level `POST /api/v2/data/custom-data/bulk` APPEND → [agents.md](https://agents.1health.io/public/prod/api/v2/data/custom-data/bulk/agents.md)
**Reference code:** [`lib/patient-link/token.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/patient-link/token.ts)
**Seen in:** pcp-tcm

## Pattern

1. Mint the token while the authenticated user is composing the outbound message (SMS/email) — minting always runs on **their** bearer, against a record they can already reach. Never mint from an unauthenticated path.
2. The token is opaque and carries **no session** — unlike a device hand-off ticket (see qr-device-session-handoff.md), it identifies a record and nothing more, so a leaked link exposes only that record's public-facing content, not a credential.
3. Store it under its own top-level `customData` key (a top-level `APPEND`, so it can't collide with other keys) with `issuedAt` / `expiresAt` / an optional `revoked` flag.
4. Make it **reusable**: return the existing live token instead of minting a new one on every send, so re-sending the same message doesn't invalidate a link the recipient already has.
5. Treat verification as a separate, downstream concern — the credential that minted the link is often scoped too narrowly (e.g. single-tenant) to verify it again later itself; that typically needs a more privileged, purpose-built lookup layer.

## Minimal example

```ts
export async function ensureRecordToken(caller: Caller, recordId: number): Promise<PublicToken | null> {
  const existing = await readTopLevelKey(caller, recordId, "publicAccessToken")
  if (existing && !existing.revoked && Date.parse(existing.expiresAt) > Date.now()) return existing

  const fresh: PublicToken = {
    token: randomBytes(16).toString("base64url"),        // short: this rides inside an SMS
    issuedAt: new Date().toISOString(),
    expiresAt: new Date(Date.now() + SERVICE_WINDOW_MS).toISOString(),
  }
  const ok = await appendTopLevelKey(caller, recordId, "publicAccessToken", fresh)
  return ok ? fresh : null
}
```

## Gotchas

- Reusing a live token is deliberate — minting fresh on every send would silently break a link already sitting in someone's inbox.
- The client's cookie-reading `authFetch` doesn't run here either: minting is server-side, so attach the caller's bearer directly and still resolve the base URL per call.
- A missing `revoked`/expiry check on the verifying side turns "long-lived" into "forever" — always check both, not just presence of a token.
- Keep this key top-level and separate from any other namespaced blob on the same record — the two are written independently and must not clobber each other.

## Related

- [qr-device-session-handoff.md](qr-device-session-handoff.md)
- Concepts: [setup/auth-and-launch.md](../setup/auth-and-launch.md)
