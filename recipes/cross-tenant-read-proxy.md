# Privileged read-only proxy for a blocked cross-tenant read

> **Advanced / guardrailed pattern.**

**Use when:** a read your product needs is tenant-scoped on 1health's side, so a lower-privileged
caller's own token is refused it (verified, not assumed) — and you want it to work for every role
without changing anyone's 1health role.
**Routes:** composes an existing read, `POST /api/v2/query` (see
[query-the-data-graph.md](query-the-data-graph.md)), plus a resource-specific `GET .../configuration`
call; the proxy itself is your own server route, not a new 1health route.
**Reference code:** [`app/api/step-config/route.tsx`](https://github.com/Tachin-ai-Corporation/v0-1health-secure-share/blob/main/app/api/step-config/route.tsx#L86) · [`lib/api/step-subscriptions.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-secure-share/blob/main/lib/api/step-subscriptions.ts#L347)
**Seen in:** v0-1health-secure-share

## Pattern

1. **Verify the read is actually blocked** for the role you need before building this — it trades a
   real security boundary for convenience, and earns its place only once confirmed refused.
2. Factor the query-building and response-parsing into one small, **side-effect-free** module that
   both the client's user-token path and the server's service-token path import, so the two can
   never quietly drift apart.
3. Gate the route behind a **feature flag** with an explicit, environment-aware default (e.g. on in
   demo, off in prod) so it ships dark and gets verified before it's live everywhere.
4. Keep the privileged token **read-only**, scoped to exactly this query — never let it grow into a
   general authenticated-fetch passthrough. Never return or log it.
5. On any non-authoritative outcome (flag off, no token, network error, non-2xx) return a "fall
   back" signal, not an empty result — only a clean, successful read should stop the client's own
   path from running. Leave every **write** on the caller's own token, untouched.

## Minimal example

```ts
// shared, zero I/O — imported by both the client path and the server route
export function buildLookupQuery(id: number) { /* returns the /query body */ }
export function parseLookupResult(json: unknown): Result | null { /* … */ }

// app/api/resource-lookup/route.ts — server, service token, read-only, flag-gated
export async function POST(req: Request) {
  const { id } = await req.json()
  if (!flagEnabled() || !serviceToken()) return Response.json({ ok: false, disabled: true })

  const res = await fetch(`${baseUrl()}/api/v2/query`, {
    method: "POST",
    headers: { Authorization: `Bearer ${serviceToken()}`, "Content-Type": "application/json" },
    body: JSON.stringify(buildLookupQuery(id)),
  })
  if (!res.ok) return Response.json({ ok: false, error: `HTTP ${res.status}` }, { status: 502 })
  return Response.json({ ok: true, result: parseLookupResult(await res.json()) })
}

// client — tries the privileged route, falls back to its own (more limited) user-token read
async function resolve(id: number) {
  const svc = await fetch("/api/resource-lookup", { method: "POST", body: JSON.stringify({ id }) }).then((r) => r.json())
  return svc.ok ? svc.result : resolveWithUserToken(id)
}
```

## Gotchas

- This is a **named, scoped exception** to "1health is the only backend, `/api/token` is the only
  route with a secret" — not a precedent for more server routes; keep it read-only.
- Distinguish "privileged read confirmed nothing's there" from "path unavailable right now" — only
  the first should stop the client's own fallback from running.
- The shared query/parse module must do **zero** I/O — the moment it fetches anything itself, the
  two callers can drift again.

## Related

- [split-identity-service-key.md](split-identity-service-key.md) · [server-side-authorization.md](server-side-authorization.md) · [query-the-data-graph.md](query-the-data-graph.md)
