# Proxy a curated knowledge base with open reads, gated writes

> **Advanced / guardrailed pattern.**

**Use when:** you curate a reference corpus behind a third-party vendor key, want any signed-in
user to read it, but want create/edit/retire restricted to admins — with 1health holding only a
citation, never the content itself.
**Routes:** n/a — your own proxy route(s) forwarding to the vendor API; 1health is only involved
through your own caller resolution.
**Reference code:** [`lib/corpus/proxy.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/lib/corpus/proxy.ts#L52) · [`lib/corpus/access.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/lib/corpus/access.ts#L34)
**Seen in:** expertdx-ordering-provider

## Pattern

1. Hold the vendor key in a server-only module with its own "is this configured" check, so a
   missing key fails soft (503) instead of a raw 500.
2. Split the gate by intent: **reads** need only a valid 1health session (see
   [server-side-authorization.md](server-side-authorization.md)); **writes** additionally need a
   real authorization decision — the vendor's own permission check is a backstop, never yours.
3. Wrap both shapes in one helper each (`handleRead`, `handleWrite`) so a new route can't skip the
   gate: resolve the caller, check the write gate if needed, call the vendor, relay its response
   verbatim.
4. Validate anything you splice into the vendor's own path (a slug/id from the URL) — treat it as
   untrusted. Store only a reference to it in 1health, never a copy of the vendor's content.

## Minimal example

```ts
// lib/knowledge-base/proxy.ts — server-only
import "server-only"
import { requireCaller } from "@/lib/auth/session"
import { canCurate } from "./access"
import { vendorFetch, hasVendorKey } from "./server"

async function relay(res: Response) {
  const text = await res.text()
  return new Response(text || null, { status: res.status, headers: { "Content-Type": "application/json" } })
}

export async function handleRead(build: () => Promise<Response>) {
  if (!hasVendorKey()) return Response.json({ error: "Not connected yet" }, { status: 503 })
  await requireCaller() // any signed-in user may read
  return relay(await build())
}

export async function handleWrite(build: () => Promise<Response>) {
  if (!hasVendorKey()) return Response.json({ error: "Not connected yet" }, { status: 503 })
  const caller = await requireCaller()
  if (!canCurate(caller)) return Response.json({ error: "Admins only" }, { status: 403 })
  return relay(await build())
}
```

## Gotchas

- The vendor's own 403 is a backstop, not your authorization — resolve+authorize the caller
  yourself before forwarding a write.
- Validate every path segment forwarded into the vendor URL — an unvalidated id is a
  path-injection risk into someone else's API.
- Keep "not configured" (503), "forbidden" (403), and "vendor error" (relayed status) distinct.

## Related

- [server-side-authorization.md](server-side-authorization.md) · [auth-forcing-route-wrapper.md](auth-forcing-route-wrapper.md) · [deidentify-before-external-ai.md](deidentify-before-external-ai.md)
