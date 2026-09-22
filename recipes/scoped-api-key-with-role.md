# Scoped API key with an explicit role

**Use when:** minting a long-lived API key/token that should carry a specific, limited role —
never the platform's default.
**Routes:** `GET /api/v2/access-control/role/all` → [agents.md](https://agents.1health.io/public/prod/api/v2/access-control/role/all/agents.md) · `POST /api/v2/token` → [agents.md](https://agents.1health.io/public/prod/api/v2/token/agents.md)
**Reference code:** [`lib/api/onboarding.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/api/onboarding.ts#L436) (`fetchPatientVaultRoleId`, `createApiToken`)
**Seen in:** patient-vault

## Pattern

1. List the **active tenant's** access-control roles and find the one you want by exact name. Role
   ids are **tenant-specific** — never hardcode one or infer it from the environment.
2. **Fail closed.** If the role can't be resolved, throw rather than proceeding — omitting
   `acRoleIds` on token creation does not mean "no role," it makes the platform default the new key
   to **System Admin**, the opposite of least-privilege.
3. Mint the token, passing the resolved id(s) in `acRoleIds`.
4. A token's value is returned **only at creation** and can never be read back. If minting collides
   on a name already in use, retry with a disambiguated name — don't try to "recover" the old value.

## Minimal example

```ts
async function fetchRoleIdByName(roleName: string): Promise<number> {
  const res = await callApi<{ id?: number; roleName?: string }[]>(
    "roles/fetch",
    "/api/v2/access-control/role/all?page=0&limit=200&excludeSystemRoles=false",
  )
  const role = res.success ? res.data?.find((r) => r.roleName === roleName) : undefined
  if (typeof role?.id !== "number") {
    // Fail closed: never mint a token without an explicit role.
    throw new Error(`Access-control role "${roleName}" was not found for the active tenant`)
  }
  return role.id
}

async function createScopedApiKey(name: string, roleName: string) {
  const acRoleIds = [await fetchRoleIdByName(roleName)]
  const res = await callApi<{ token?: { tokenValue?: string } }>("token/create", "/api/v2/token", {
    method: "POST",
    body: JSON.stringify({ name, acRoleIds }),
  })
  const tokenValue = res.data?.token?.tokenValue
  if (!res.success || !tokenValue) throw new Error(res.error ?? "API key created but no value was returned")
  return tokenValue // shown once — persist/display it now; it cannot be read back later
}
```

## Gotchas

- **Omission is not a safe default.** No `acRoleIds` silently mints a System-Admin-equivalent key —
  always resolve and pass a role id explicitly.
- **Role ids are per-tenant.** Resolve them fresh after any tenant switch; never cache one across
  tenants or environments.
- **The token value is one-time-visible.** Design your UI/flow around "show once, then only a
  masked/id form remains" — there's no reveal-later endpoint.
- **A name collision on create is only detectable by a 400** you pattern-match on message text —
  there's no separate "check name availability" call.

## Related

- [tenant-provisioning.md](tenant-provisioning.md), [register-console-application.md](register-console-application.md) — the same one-time-secret shape.
- [split-identity-service-key.md](split-identity-service-key.md) — when the resulting key itself becomes a privileged service credential.
