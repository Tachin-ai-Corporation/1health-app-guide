# Cross-origin tenant switch

> **Advanced / guardrailed pattern.**

**Use when:** your app runs cross-origin from the 1health platform (a separate SPA, not the
platform's own frontend) and needs to move the current session onto a different tenant.
**Routes:** `GET /api/v2/user/switch-tenant/{id}` → [agents.md](https://agents.1health.io/public/prod/api/v2/user/switch-tenant/agents.md) · `GET /api/v2/user/myself` → [agents.md](https://agents.1health.io/public/prod/api/v2/user/myself/agents.md) (verify)
**Reference code:** [`lib/api/onboarding.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/api/onboarding.ts#L316) (`switchTenant`)
**Seen in:** patient-vault

## Pattern

1. Call the switch-tenant endpoint for the target tenant id with `revokeToken=false`, keeping your
   current token valid so you have something to refresh from if the response carries no new token.
2. On a same-origin platform frontend, new tokens usually arrive via `Set-Cookie` on the platform's
   own domain — **invisible to a cross-origin caller.** Don't depend on that; treat a 200 status as
   only step one.
3. The response body carries the new tokens directly: `{ auth: { access_token, refresh_token, ... }, user: {...} }`. Read `auth.access_token` — treat a response with no usable token as a hard
   failure, not something to guess at from a JWT-shaped string elsewhere in the body.
4. If the body carries no usable token, fall back to your normal OAuth refresh grant — after a
   successful switch, the refreshed token comes back scoped to the new tenant context.
5. **Verify the token's own tenant claim before you keep it** — a refresh grant can stamp a stale,
   previously-persisted tenant context, so check the claim itself, not just a subsequent read.
   Treat a mismatch exactly like a failed switch (discard it), never adopt it anyway.
6. Re-fetch the current-user endpoint and confirm its tenant context id actually matches the
   target, retrying the refresh once or twice with a short backoff for propagation lag before
   reporting failure.
7. **Purge every client-side cache** — the query/result cache and any identity/tenant state, not
   just the token — before loading anything for the new tenant. Skipping this is the single most
   likely way to leak one tenant's cached data into another tenant's screen, even when every API
   call itself is correctly scoped.

## Minimal example

```ts
/** Decode a JWT's tenant claim without verifying the signature (the API already signed it). */
function tenantClaimOf(jwt: string): number | null {
  const payload = JSON.parse(atob(jwt.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")))
  return payload.tenant_id ?? payload.tenantId ?? null // confirm the exact claim name against a real token
}

async function switchTenant(tenantId: number): Promise<boolean> {
  const res = await authFetch(`${getOneHealthBaseUrl()}/api/v2/user/switch-tenant/${tenantId}?revokeToken=false`)
  if (!res.ok) throw new Error(`Failed to switch tenant: ${res.status}`)

  // Cross-origin callers can't rely on Set-Cookie — the new tokens are in the body instead.
  const body: { auth?: { access_token?: string }; user?: unknown } = await res.json()
  const accessToken = body.auth?.access_token
  if (accessToken && tenantClaimOf(accessToken) !== tenantId) {
    throw new Error("Switch response token claims the wrong tenant — treat this as a failed switch")
  }
  if (accessToken) persistAccessToken(accessToken)

  for (let attempt = 1; attempt <= 3; attempt++) {
    if (!accessToken) await refreshToken() // re-issues a token scoped to the now-active tenant
    const me = await callApi<{ tenantContext?: { id?: number } }>("user/myself", "/api/v2/user/myself")
    if (me.success && me.data?.tenantContext?.id === tenantId) {
      purgeAllClientCaches() // query cache + identity/tenant state — before anything else loads
      return true
    }
    await new Promise((r) => setTimeout(r, 600)) // context propagation lag
  }
  throw new Error(`Switched, but the active tenant did not update to ${tenantId}`)
}
```

## Gotchas

- **Cross-origin cookie delivery on the switch call is unreliable by construction** — never assume
  the new token arrived via `Set-Cookie`; scan the body or fall back to a refresh grant.
- **The new tenant context can take a moment to propagate.** A `myself` check immediately after
  switching can still show the old tenant — retry with backoff before giving up.
- **`revokeToken=false` matters.** Revoking immediately removes your ability to fall back to a
  refresh grant if the body has no token.
- **Purging caches is not optional.** A component can render tenant A's cached list under tenant
  B's now-active context for however long it takes the new fetch to land, unless you clear the
  query cache and identity/tenant state as part of the same operation, before fetching anything new.
- **Verify the token's own tenant claim, not just a later `myself` poll** — a refresh grant can
  hand back a token still stamped with a stale server-side context; check the claim before you
  persist it, and treat a mismatch as a failed switch rather than adopting it anyway.
- **On any failure in the switch, the safe fallback is a full local sign-out**, not "stay on the
  old tenant" — treat a failed switch as untrustworthy state, not a no-op.

## Related

- [tenant-provisioning.md](tenant-provisioning.md), [scoped-api-key-with-role.md](scoped-api-key-with-role.md)
- [split-identity-service-key.md](split-identity-service-key.md) — the broader privileged/cross-context credential pattern this sits alongside.
- Concepts: [setup/auth-and-launch.md](../setup/auth-and-launch.md).
