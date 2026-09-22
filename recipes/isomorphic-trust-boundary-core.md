# Isomorphic trust-boundary core

> **Advanced / guardrailed pattern.**

**Use when:** the same query-building + response-parsing logic must run identically under two different credentials — the end user's own token in the browser, and a privileged service token in a server route — and the two must never drift apart.
**Routes:** `POST /api/v2/query` → [agents.md](https://agents.1health.io/public/prod/api/v2/query/agents.md) (the shared module itself performs no I/O — see Pattern)
**Reference code:** [`lib/api/step-resolution-core.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-secure-share/blob/main/lib/api/step-resolution-core.ts) (the pure core) · [`app/api/step-config/route.tsx`](https://github.com/Tachin-ai-Corporation/v0-1health-secure-share/blob/main/app/api/step-config/route.tsx) (server caller) · [`lib/api/step-subscriptions.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-secure-share/blob/main/lib/api/step-subscriptions.ts) (client caller)
**Seen in:** secure-share

## Pattern

1. Find the logic that must produce identical results no matter which credential runs it — typically a multi-hop `/query` traversal plus its response parser.
2. Extract exactly that into a module with **no network call, no credential/cookie access**, and no `"use client"`/Node-only import — pure functions: request body in, parsed result out.
3. Import it from the client path (executes via `authFetch` under the user's own token) AND from a server route that executes it with a privileged/service token — for callers whose own token can't resolve the same record.
4. Resolve canonical relationships structurally (the real graph edge), never a tenant-scoped convenience field on the payload — the convenience field is exactly what drifts across orgs.
5. Keep the privileged path read-only, behind a feature flag, with a fallback to the client path — the shared core is what guarantees the fallback produces the identical shape.

## Minimal example

```ts
// resolve-parent-core.ts — ISOMORPHIC: no fetch, no cookies, no secrets.
export function buildParentQuery(childId: number) {
  return {
    key: "ChildType", filter: `id==${childId}`, attributes: ["id"],
    relationships: [{ key: "ChildType.ChildHasCanonicalParent.ParentType", attributes: ["id"], limit: 1 }],
    limit: 1, offset: 0,
  }
}
export function parseParentId(data: unknown): number | null {
  const row = (data as any)?.data?.[0]
  const id = row?.relationships?.["ChildType.ChildHasCanonicalParent.ParentType"]?.[0]
    ?.instance?.attributes?.["ChildHasCanonicalParent.ParentType.id"]
  return typeof id === "number" ? id : null
}

// CLIENT: authFetch(...) under the user's own token, using the two functions above.
// SERVER (app/api/.../route.ts): fetch(...) with `Authorization: Bearer <serviceToken>`,
//         the SAME two functions — never a re-implementation that could drift.
```

## Gotchas

- Keep the core free of `"use client"`, `document`, and any credential import — one slip makes it unsafe to import from the server bundle.
- Type-only imports from a client-facing sibling file are erased at compile time, so a server route can import that module's *types* without pulling in its client runtime.
- The privileged path is a scoped, named exception to "1health is the only backend" — read-only, flagged, with a fallback — not a license for general-purpose server logic.

## Related

- [query-the-data-graph.md](query-the-data-graph.md)
- [cross-tenant-read-proxy.md](cross-tenant-read-proxy.md)
- [server-side-authorization.md](server-side-authorization.md)
- Concepts: [setup/auth-and-launch.md](../setup/auth-and-launch.md)
