# Split identity: user token vs. privileged service key

> **Advanced / guardrailed pattern.**

**Use when:** some operations must run under a privileged service/System-Admin credential instead
of the caller's own token — the platform refuses the op to their role, there's no caller session
yet, or you're verifying a claim the caller made — and the privilege needs to stay auditable rather
than spread through the codebase by habit.
**Routes:** n/a — an architecture pattern for *which credential* calls 1health, not a route.
**Reference code:** none public — see the Minimal example.
**Seen in:** A specialist-consult ordering app (narrower forms in a secure file-sharing app, a transitional-care app)

## Pattern

1. Default to the caller's own token for everything; the service key is the exception, chosen
   per-operation — never a blanket "server routes use the service key" rule.
2. For every call that must use it, record a reason from a **fixed, small vocabulary**: the platform
   refuses this to the caller's role; there's no session yet; it's a cross-tenant read only the
   service can do; it's verifying a claim the caller made. "Convenient" is not on the list.
3. Make that record a real module the code imports — an `operation → reason` manifest — and add an
   automated check, run in CI, that fails if a service-key call site isn't listed, or a listed
   entry no longer matches real code. A list nothing enforces goes stale.
4. Put the privileged transport behind a server-only module. **Never log, return, or otherwise let
   the key reach a response body or client bundle.**
5. Content a *person* authored (an upload, a comment) still goes through **their own token**, even
   in an app that's mostly service-key-driven, so the platform's audit fields name the right party.
6. The key's privilege is not a substitute for authorization — pair every privileged call with the
   ownership check from [server-side-authorization.md](server-side-authorization.md).

## Minimal example

```ts
// privileged-ops.ts — the manifest, imported by the code AND by a CI check script
type Basis = "role-refused" | "no-session" | "cross-tenant" | "verifies-claim" // "convenient" is not on the list
export type PrivilegedOp = "records/create" | "records/authorize"

// Typed by the union above, so an op without a recorded basis doesn't compile.
export const PRIVILEGED_OPS: Record<PrivilegedOp, { basis: Basis; note: string }> = {
  "records/create": { basis: "role-refused", note: "The platform rejects this create for the caller's role (measured)." },
  "records/authorize": { basis: "verifies-claim", note: "Decides whether the caller owns the record; it can't run as the caller." },
}

// service-transport.ts — server-only; the ONE place the key touches a request
import "server-only"
export async function serviceCall<T>(op: PrivilegedOp, path: string, init: RequestInit = {}): Promise<T> {
  if (!(op in PRIVILEGED_OPS)) throw new Error(`${op} is not in the privileged-operations manifest`)
  const signed = new Headers(init.headers)
  signed.set("Authorization", `Bearer ${process.env.SERVICE_KEY}`)
  const res = await fetch(`${baseUrl()}${path}`, { ...init, headers: signed })
  return (await res.json()) as T
}
```

## Gotchas

- **A leaked service key is a full-tenant breach**, not a per-user one — treat it accordingly.
- An enforcement script nobody runs in CI is documentation, not a guardrail.
- If a new call doesn't fit one of your fixed reasons, that's a signal the operation shouldn't be
  privileged — don't invent a reason to fit the call.
- Don't let user-authored content ride the service key just because the route already holds it.

## Related

- [server-side-authorization.md](server-side-authorization.md) · [auth-forcing-route-wrapper.md](auth-forcing-route-wrapper.md) · [cross-tenant-read-proxy.md](cross-tenant-read-proxy.md) · [baa-status-split-identity.md](baa-status-split-identity.md)
