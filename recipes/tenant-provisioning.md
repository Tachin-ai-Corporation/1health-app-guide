# First-run tenant provisioning

> **Advanced / guardrailed pattern.**

**Use when:** your app must create a brand-new tenant/organization for a first-time user on the
fly (developer-console-style onboarding), rather than assuming the user already has one.
**Routes:** `POST /api/v2/tenant` → [agents.md](https://agents.1health.io/public/prod/api/v2/tenant/agents.md) (multipart) · `GET /api/v2/tenant/all` (not yet in the published docs)

> **⚠ Not yet in 1health's published API docs:** `GET /api/v2/tenant/all`. 1health supports it for third-party apps, but agents.1health.io has no page for it yet — the shape shown here comes from working apps. Test it against demo before you rely on it.

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
3. Tenant names are **globally unique**. In an **unattended** flow, retry a name-taken 400 with a
   disambiguating random suffix rather than failing outright. In a **human-facing create form**,
   don't auto-retry — surface the raw collision error and let the person pick a new name
   themselves; auto-retrying is for flows with no one there to make that choice.
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

// This is the UNATTENDED variant (auto-retries a name collision). A human-facing create form
// should call the same POST once and surface a 400 as-is, letting the person pick a new name.
async function ensureTenant(displayName: string, primaryEmail: string): Promise<number> {
  const all = await callApi<{ id: number; name?: string }[]>("tenant/all", "/api/v2/tenant/all")
  const existing = all.success ? matchExistingTenantId(all.data ?? []) : null
  if (existing) return existing

  for (let attempt = 1, name = displayName; attempt <= 5; attempt++) {
    const form = new FormData()
    form.append("dto", JSON.stringify({
      name,
      primaryCorporateEmail: primaryEmail,
      headquartersAddress: DEFAULT_HQ_ADDRESS,
      types: ["Health Provider"], // required even when it isn't otherwise validated client-side
      // no `subdomain` — omitting it skips DNS/OAuth-client provisioning; a generated one can
      // overflow the platform's length limit, so only set it when you deliberately want that.
    }))
    const res = await authFetch(`${getOneHealthBaseUrl()}/api/v2/tenant`, { method: "POST", body: form })
    if (res.ok) {
      const body = await res.json()
      return body.tenant?.id ?? body.id // accept both the nested and the flattened response shape
    }
    const errorBody = await res.text()
    if (res.status === 400 && /already exists/i.test(errorBody)) { name = `${displayName} ${randomSuffix()}`; continue }
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
- **Send the `types` array** even though nothing client-side validates it against your other
  fields — omitting it is easy to miss since the call can still succeed without it in some cases.
- **The response shape isn't uniform** — some deployments return a nested `{ tenant: { id } }`,
  others a flattened `{ id }`. Accept both with a fallback rather than assuming one.
- **Only set `subdomain` when you deliberately want it** — its presence is what triggers
  DNS/OAuth-client provisioning server-side, and a generated value can overflow the platform's
  length limit. Omit it entirely for a tenant that doesn't need its own public subdomain.
- **Treat this as advanced and guardrailed**: creating tenants is powerful and hard to undo cleanly
  — gate it behind a clear, one-time "first run" signal, not something a user can trigger repeatedly
  by accident.

## Related

- [look-then-create.md](look-then-create.md), [cross-origin-tenant-switch.md](cross-origin-tenant-switch.md), [scoped-api-key-with-role.md](scoped-api-key-with-role.md)
