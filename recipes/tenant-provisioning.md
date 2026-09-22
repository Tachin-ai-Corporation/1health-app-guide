# First-run tenant provisioning

> **Advanced / guardrailed pattern.**

**Use when:** your app must create a brand-new tenant/organization for a first-time user on the
fly (developer-console-style onboarding), rather than assuming the user already has one.
**Routes:** `POST /api/v2/tenant` → [agents.md](https://agents.1health.io/public/prod/api/v2/tenant/agents.md) (multipart) · `GET /api/v2/tenant/all` → [route docs](https://agents.1health.io/public/prod/api/manifest.md)
**Reference code:** [`lib/api/onboarding.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/api/onboarding.ts#L116) (`createTenant`, `matchExistingVaultId`, `findExistingVaultId`)
**Seen in:** patient-vault

## Pattern

1. Before creating anything, list the user's accessible tenants and check for one that already
   matches your app's naming convention (e.g. its name contains a fixed marker string). Reuse it —
   see [look-then-create.md](look-then-create.md) — converging deterministically (lowest id) if more
   than one matches, so repeated launches never fork into duplicate orgs.
2. Only when none exists, POST the tenant-create endpoint with a seeded, valid default payload (e.g.
   a placeholder pre-validated address). This call runs unattended, so it can't rely on interactive
   form input for fields the platform requires but your flow has no natural source for.
3. Tenant names are **globally unique**. On a name-taken 400, retry with a disambiguating random
   suffix rather than failing the whole onboarding.
4. Immediately follow with the tenant-switch step — a created tenant isn't useful until the caller's
   session is actually scoped to it. See
   [cross-origin-tenant-switch.md](cross-origin-tenant-switch.md).

## Minimal example

```ts
const VAULT_NAME_MARKER = "your app name"
const BOOTSTRAP_TENANT_ID = 1 // the shared tenant every new user lands on before setup

function matchExistingTenantId(tenants: { id: number; name?: unknown }[]): number | null {
  const matches = tenants
    .filter((t) => t.id !== BOOTSTRAP_TENANT_ID && typeof t.name === "string" && t.name.toLowerCase().includes(VAULT_NAME_MARKER))
    .sort((a, b) => a.id - b.id)
  return matches[0]?.id ?? null
}

async function ensureTenant(displayName: string, primaryEmail: string): Promise<number> {
  const all = await callApi<{ id: number; name?: string }[]>("tenant/all", "/api/v2/tenant/all")
  const existing = all.success ? matchExistingTenantId(all.data ?? []) : null
  if (existing) return existing

  for (let attempt = 1, name = displayName; attempt <= 5; attempt++) {
    const form = new FormData()
    form.append("dto", JSON.stringify({ name, primaryCorporateEmail: primaryEmail, headquartersAddress: DEFAULT_HQ_ADDRESS }))
    const res = await authFetch(`${getOneHealthBaseUrl()}/api/v2/tenant`, { method: "POST", body: form })
    if (res.ok) return (await res.json()).tenant?.id
    const body = await res.text()
    if (res.status === 400 && /already exists/i.test(body)) { name = `${displayName} ${randomSuffix()}`; continue }
    throw new Error(`Failed to create tenant: ${res.status}`)
  }
  throw new Error("Could not find an available tenant name")
}
```

## Gotchas

- **Auto-provisioning on "landed on the shared bootstrap tenant" will fork a new org on every
  launch** unless you first check for an existing one by your app's naming convention.
- **The create call can require fields with no natural source in an unattended flow** (like a
  geocoded/validated address) — seed a known-good placeholder rather than letting validation fail.
- **Treat this as advanced and guardrailed**: creating tenants is powerful and hard to undo cleanly
  — gate it behind a clear, one-time "first run" signal, not something a user can trigger repeatedly
  by accident.

## Related

- [look-then-create.md](look-then-create.md), [cross-origin-tenant-switch.md](cross-origin-tenant-switch.md), [scoped-api-key-with-role.md](scoped-api-key-with-role.md)
