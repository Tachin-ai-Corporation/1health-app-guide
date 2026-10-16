# Resolve the caller server-side and re-derive resource ownership

**Use when:** a server route acts with more privilege than the caller has (a service key, or simply
by virtue of being a server) and must decide whether *this* caller may see or change *this*
resource.
**Routes:** n/a — pattern for establishing identity; typically backed by `GET /api/v2/user/myself`
→ [agents.md](https://agents.1health.io/public/prod/api/v2/user/myself/agents.md) and `GET /api/v2/tenant` → [agents.md](https://agents.1health.io/public/prod/api/v2/tenant/agents.md) to resolve who's asking.
**Reference code:** none public — see the Minimal example.
**Seen in:** A specialist-consult ordering app

## Pattern

1. Take the caller's own access token from an **httpOnly** cookie (or an `Authorization` header) —
   never trust a non-httpOnly cookie's contents (e.g. a client-writable "current org" cookie) as an
   identity fact. Those exist for UI convenience only; the browser can rewrite them at will.
2. **Re-validate that token against 1health itself** on every request that needs identity (a "who am
   I" call, plus a tenant lookup if org membership matters). A forged or expired token fails there,
   not in your own code — you never decode or trust the token's contents directly.
3. Treat "authenticated but not yet fully onboarded" (no organization yet) as a **real, distinct**
   state, not a synonym for "not signed in" — collapsing them makes the onboarding screen
   unreachable.
4. For any resource-scoped operation, **re-derive ownership from the resource itself**: read it (with
   whatever credential can see it) and pull out whose it is, then compare that to the caller's own
   resolved identity. Never accept an ownership claim from the request body or a query param.
5. Make "no such resource" and "exists, but not yours" **indistinguishable** in the response whenever
   confirming existence itself would leak something the caller has no business knowing.
6. Put all of this in one module every privileged route imports, so the check is identical everywhere
   instead of reimplemented — and possibly gotten wrong — per route.

## Minimal example

```ts
// lib/auth/session.ts — server-only
import "server-only"
import { cookies } from "next/headers"

export interface SignedInUser { userId: number; orgId: number | null; tenantId: number }
export class NotSignedInError extends Error {} // → 401
export class AccessDeniedError extends Error {} // → 403

// Ask 1health whose token this is. null = missing, expired or forged — 1health decides, not us.
async function whoAmI(token: string | undefined) {
  if (!token) return null
  const res = await fetch(`${baseUrl()}/api/v2/user/myself`, { headers: { Authorization: `Bearer ${token}` } })
  const me = res.ok ? await res.json() : null
  return me?.id ? me : null
}

export async function requireSignedInUser(): Promise<SignedInUser> {
  const me = await whoAmI((await cookies()).get("access_token")?.value) // httpOnly cookie only
  if (!me) throw new NotSignedInError()
  // orgId may be null: signed in but not onboarded yet — a real state, not "signed out".
  return { userId: me.id, orgId: me.tenantContext?.organizationId ?? null, tenantId: me.tenantContext.id }
}

// Re-derive ownership from the RESOURCE, never from the request.
export async function authorizeRecord(user: SignedInUser, recordId: number) {
  const record = await serviceCall("records/authorize", "/api/v2/query", {
    method: "POST",
    body: JSON.stringify({ key: "Record", filter: `id==${recordId}`, attributes: ["id", "ownerOrgId"] }),
  })
  const owner = extractOwnerOrgId(record)
  const owned = owner != null && owner === user.orgId
  if (!owned) throw new AccessDeniedError("No such record") // same answer for "missing" and "not yours"
  return record
}
```

## Gotchas

- A non-httpOnly cookie is a UI hint, never an authorization input — the browser can set it to
  anything.
- "No organization yet" and "not signed in" are different states; conflating them breaks onboarding.
- Re-derive ownership from the resource on every call — don't cache a prior decision across requests.
- Return the same error for "doesn't exist" and "exists but isn't yours" whenever existence itself is
  sensitive.

## Related

- [auth-forcing-route-wrapper.md](auth-forcing-route-wrapper.md) · [split-identity-service-key.md](split-identity-service-key.md) · [../setup/auth-and-launch.md](../setup/auth-and-launch.md)
