# Restrict self-registration to approved email domains

> **Advanced / guardrailed pattern.**

**Use when:** you want anyone with an address on an approved domain to self-register into a
tenant, without inviting each person individually — and to shut that door for every other domain.
**Routes:** `POST /api/graphql` → [agents.md](https://agents.1health.io/public/prod/api/graphql/agents.md) — a query/mutation against the tenant configuration record's `allowedDomains` field
**Reference code:** [`lib/api/tags.ts`](https://github.com/Tachin-ai-Corporation/v0-trc-care-coordinator/blob/main/lib/api/tags.ts#L32) (the general authenticated-GraphQL-call shape this reuses, against a different record type)
**Seen in:** 1health platform usage

## Pattern

1. Read the tenant's configuration record via GraphQL, filtered to the current tenant, projecting
   `allowedDomains`.
2. **`allowedDomains` is a JSON array serialized as a string**, not a native list —
   `JSON.parse` on read, `JSON.stringify` on write. A missing row, `null`, or malformed JSON all
   mean "no restriction configured" — treat them as an empty list, not an error.
3. Write with a targeted mutation: filter by the tenant's own id and cap `maxRecordsToUpdate` at
   1, so a filter mistake can't silently rewrite more than one tenant's configuration.
4. Hand out the tenant's normal hosted self-registration link with a flow/referral query parameter
   tagged for this audience, instead of inviting each person — anyone whose email domain matches
   the list can complete registration through it.
5. Check every GraphQL response for a body-level `errors` array — a domain-list update failure can
   arrive as HTTP 200 (see [graphql-read-path.md](graphql-read-path.md)).

## Minimal example

```ts
import { authFetch, getOneHealthBaseUrl } from "@/lib/auth-client"

async function readDomainAllowlist(tenantId: number): Promise<string[]> {
  const baseUrl = getOneHealthBaseUrl()
  const res = await authFetch(`${baseUrl}/api/graphql`, {
    method: "POST",
    body: JSON.stringify({
      query: `query($f: String!) { SysTenantConfiguration(filter: $f) { records { id allowedDomains } } }`,
      variables: { f: `tenant==${tenantId}` },
    }),
  })
  const { data, errors } = await res.json()
  if (errors?.length) throw new Error(errors.map((e: any) => e.message).join("; "))
  const raw = data?.SysTenantConfiguration?.records?.[0]?.allowedDomains
  if (!raw) return [] // no row yet, or nothing configured
  try { return JSON.parse(raw) } catch { return [] } // malformed also means "unrestricted"
}

async function setAllowedDomains(tenantId: number, domains: string[]) {
  const baseUrl = getOneHealthBaseUrl()
  const res = await authFetch(`${baseUrl}/api/graphql`, {
    method: "POST",
    body: JSON.stringify({
      query: `mutation($rsql: String!, $record: SysTenantConfigurationInput!) {
        UpdateSysTenantConfigurationRecords(rsql: $rsql, record: $record, maxRecordsToUpdate: 1) { id }
      }`,
      variables: { rsql: `tenant==${tenantId}`, record: { allowedDomains: JSON.stringify(domains) } },
    }),
  })
  const { errors } = await res.json()
  if (errors?.length) throw new Error(errors.map((e: any) => e.message).join("; "))
}
```

## Gotchas

- **`allowedDomains` round-trips as a string** — a raw pass-through without `JSON.parse`/`JSON.stringify` silently breaks both read and write.
- **No config row yet is the common case for a new tenant** — treat a missing record the same as
  an empty allowlist, not an error.
- **GraphQL errors arrive under `response.data.errors` at HTTP 200**, not as a REST-style status
  code — check it explicitly.
- **`maxRecordsToUpdate` is your only guard against a filter mistake fanning out to more than one
  tenant** — always set it.

## Related

- [graphql-read-path.md](graphql-read-path.md) — the GraphQL call shape and its error-handling gotcha.
- [tenant-security-policy.md](tenant-security-policy.md) — another tenant-wide admin setting, same
  privileged/confirm-before-write spirit.
- [add-users-to-a-tenant.md](add-users-to-a-tenant.md) — what happens once someone's domain clears
  this gate.
