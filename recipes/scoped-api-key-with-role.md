# Scoped API key with an explicit role

**Use when:** minting a long-lived API key/token that should carry a specific, limited role —
never the platform's default.
**Routes:** `GET /api/v2/access-control/role/all` → [agents.md](https://agents.1health.io/public/prod/api/v2/access-control/role/all/agents.md) · `POST /api/v2/token` (not yet in the published docs) · `GET /api/v2/token` (not yet in the published docs)

> **⚠ Not yet in 1health's published API docs:** `POST /api/v2/token` and `GET /api/v2/token`. 1health supports them for third-party apps, but agents.1health.io has no page for them yet — the shapes shown here come from working apps. Test them against demo before you rely on them.

**Reference code:** [`lib/api/onboarding.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/api/onboarding.ts#L436) (`fetchPatientVaultRoleId`, `createApiToken`)
**Seen in:** patient-vault

## Pattern

1. List the **active tenant's** access-control roles with `excludeSystemRoles=true`, so the
   platform's own reserved roles are hidden server-side instead of you having to filter them out by
   name, and find the one you want by exact name. Role ids are **tenant-specific** — never hardcode
   one or infer it from the environment.
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
    "/api/v2/access-control/role/all?page=0&limit=200&excludeSystemRoles=true",
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
- **A role's shape differs depending on where you read it from.** The role list above returns
  `{ id, roleName }`; a token's own attached roles (read back via `GET /api/v2/token`) return
  `{ id, name }` for the same concept — code copy-pasted between the two contexts will find one of
  them `undefined`.
- **A second, separate credential family — "external API keys" — also exists**, with its own
  create/update/delete calls and its own grid-based list; this recipe covers only the role-scoped
  personal/API token.
- **This recipe's rule is fail-closed, with no exception.** Some onboarding flows elsewhere choose
  to mint an unscoped key with a visible warning when a role can't be resolved — don't; throw
  instead, per step 2.

## Related

- [tenant-provisioning.md](tenant-provisioning.md), [register-console-application.md](register-console-application.md) — the same one-time-secret shape.
- [split-identity-service-key.md](split-identity-service-key.md) — when the resulting key itself becomes a privileged service credential.
