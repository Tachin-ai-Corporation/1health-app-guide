# BAA status, split by identity

> **Advanced / guardrailed pattern.**

**Use when:** you need a fast, authoritative BAA-status check — e.g. to route or gate a session — from a flag that lives on the platform's own tenant config and is only readable by a privileged service key, while the actual accept/read of the agreement must still run as the bound party.
**Routes:** observed as `GET /api/v2/tenant/sys-config?Tenant IDs=` (the literal, space-containing query key is not a typo) — confirm the exact params and doc path via the [manifest](https://agents.1health.io/public/prod/api/manifest.md) before trusting a guessed link · `GET/PUT /api/v2/agreement/_type_[/accept]` (as in [baa-gating.md](baa-gating.md))
**Reference code:** [`lib/expertdx/baa.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/lib/expertdx/baa.ts)
**Seen in:** expertdx

## Pattern

1. Recognize when a status flag and an executable action are genuinely **different operations needing different identities**: a coarse "is this org a HIPAA covered entity" flag can live on tenant config, readable only by a privileged key; the agreement itself is caller-scoped and must be read/accepted as the bound party.
2. Read the coarse flag with the privileged credential, scoped explicitly by the target tenant id. Use it as the router/gate signal only.
3. For anything that shows or executes the agreement itself — its acceptance flag, its PDF, its accept action — switch back to the caller's own token. Reading it with the privileged key reports the *service's* own acceptance, not the org's.
4. Fail closed on the privileged read too: no flag, or a failed call, means "not covered" — the safe direction for PHI.
5. Name this call explicitly in your identity manifest (see [split-identity-service-key.md](split-identity-service-key.md)) so it's auditable which operations use the privileged credential and why.

## Minimal example

```ts
// SERVICE KEY — coarse status flag, explicitly scoped by tenant id.
// `serviceKeyCall` signs the request with the privileged credential, never the caller's.
async function fetchTenantBaaStatus(
  tenantId: number,
  serviceKeyCall: (path: string) => Promise<{ data: unknown }>,
): Promise<boolean> {
  const params = new URLSearchParams({ "Tenant IDs": String(tenantId), includeAllRelations: "true" })
  const res = await serviceKeyCall(`/api/v2/tenant/sys-config?${params}`)
  const rows = Array.isArray(res.data) ? res.data : [res.data]
  const row = rows[0] as { hipaaCoveredEntity?: boolean } | undefined
  return row?.hipaaCoveredEntity === true // null/absent => not covered; fail closed
}

// CALLER TOKEN — the agreement itself must be read/accepted as the bound party.
async function fetchBaaAgreement(callerToken: string, baseUrl: string) {
  const response = await fetch(`${baseUrl}/api/v2/agreement/BAA%20Organization%20Standard`, {
    headers: { Authorization: `Bearer ${callerToken}` },
  })
  return response.ok ? response.json() : null
}
```

## Gotchas

- Reading the *agreement* endpoint with a privileged key answers for the **service's own** tenant, not the org you're checking — a wrong-answer bug, not a clean failure.
- The tenant-config flag and the agreement's own `state.accepted` are two different facts describing the same real-world event — don't assume one implies the other is readable/writable by the same identity.
- The status-read query parameter can be a literal, space-containing name (`"Tenant IDs"`) rather than a clean camelCase key — confirm exact parameter names live rather than guessing from convention.
- This pattern only earns its complexity for a genuine cross-tenant/pre-auth read; default to the single-identity flow in [baa-gating.md](baa-gating.md) otherwise.

## Related

- [baa-gating.md](baa-gating.md) — the single-identity version of this same domain.
- [split-identity-service-key.md](split-identity-service-key.md) — the general guardrails this pattern must follow.
