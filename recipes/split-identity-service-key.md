# Split identity: user token vs. privileged service key

> **Advanced / guardrailed pattern.**

**Use when:** some operations must run under a privileged service/System-Admin credential instead
of the caller's own token — the platform refuses the op to their role, there's no caller session
yet, or you're verifying a claim the caller made — and the privilege needs to stay auditable rather
than spread through the codebase by habit.
**Routes:** n/a — an architecture pattern for *which credential* calls 1health, not a route.
**Reference code:** [`lib/expertdx/identity.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/lib/expertdx/identity.ts#L60) · [`lib/expertdx/server.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/lib/expertdx/server.ts#L47)
**Seen in:** expertdx-ordering-provider (narrower forms in v0-1health-secure-share, pcp-tcm)

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
// identity.ts — the manifest, imported by the code AND a CI check script
export const SERVICE_KEY_CALLS = {
  "case/create": { reason: "PLATFORM", why: "A partner-org token cannot create a journey on our campaign." },
  "case/authorize": { reason: "TRUST", why: "Answers whether the caller owns this case — can't ask the caller." },
} as const satisfies Record<string, { reason: string; why: string }>

// server.ts — server-only; the ONE place the key touches a request
import "server-only"
export async function serviceCall<T>(context: keyof typeof SERVICE_KEY_CALLS, path: string, init: RequestInit = {}): Promise<T> {
  if (!(context in SERVICE_KEY_CALLS)) throw new Error(`${context} is not in the service-key manifest`)
  const res = await fetch(`${baseUrl()}${path}`, {
    ...init,
    headers: { ...init.headers, Authorization: `Bearer ${process.env.SERVICE_KEY}` },
  })
  return res.json() as Promise<T>
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
