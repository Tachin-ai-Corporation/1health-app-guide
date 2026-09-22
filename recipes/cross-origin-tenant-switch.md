# Cross-origin tenant switch

> **Advanced / guardrailed pattern.**

**Use when:** your app runs cross-origin from the 1health platform (a separate SPA, not the
platform's own frontend) and needs to move the current session onto a different tenant.
**Routes:** `GET /api/v2/user/switch-tenant/{id}` → [route docs](https://agents.1health.io/public/prod/api/manifest.md) · `GET /api/v2/user/myself` → [agents.md](https://agents.1health.io/public/prod/api/v2/user/myself/agents.md) (verify)
**Reference code:** [`lib/api/onboarding.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/api/onboarding.ts#L316) (`switchTenant`)
**Seen in:** patient-vault

## Pattern

1. Call the switch-tenant endpoint for the target tenant id with `revokeToken=false`, keeping your
   current token valid so you have something to refresh from if the response carries no new token.
2. On a same-origin platform frontend, new tokens usually arrive via `Set-Cookie` on the platform's
   own domain — **invisible to a cross-origin caller.** Don't depend on that; treat a 200 status as
   only step one.
3. Scan the response body defensively for a JWT-shaped string, preferring a field path that mentions
   "access," and adopt it if present.
4. If the body carries no usable token, fall back to your normal OAuth refresh grant — after a
   successful switch, the refreshed token comes back scoped to the new tenant context.
5. **Verify, don't assume.** Re-fetch the current-user endpoint and confirm its tenant context id
   actually matches the target, retrying the refresh once or twice with a short backoff for
   propagation lag before reporting failure.

## Minimal example

```ts
async function switchTenant(tenantId: number): Promise<boolean> {
  const res = await authFetch(`${getOneHealthBaseUrl()}/api/v2/user/switch-tenant/${tenantId}?revokeToken=false`)
  if (!res.ok) throw new Error(`Failed to switch tenant: ${res.status}`)

  // The new token may or may not be in the body — cross-origin callers can't rely on Set-Cookie.
  const bodyToken = extractJwtFromBody(await res.text())
  if (bodyToken) persistAccessToken(bodyToken)

  for (let attempt = 1; attempt <= 3; attempt++) {
    if (!bodyToken) await refreshToken() // re-issues a token scoped to the now-active tenant
    const me = await callApi<{ tenantContext?: { id?: number } }>("user/myself", "/api/v2/user/myself")
    if (me.success && me.data?.tenantContext?.id === tenantId) return true
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

## Related

- [tenant-provisioning.md](tenant-provisioning.md), [scoped-api-key-with-role.md](scoped-api-key-with-role.md)
- [split-identity-service-key.md](split-identity-service-key.md) — the broader privileged/cross-context credential pattern this sits alongside.
- Concepts: [setup/auth-and-launch.md](../setup/auth-and-launch.md).
