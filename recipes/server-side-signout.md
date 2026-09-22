# Complete server-side sign-out

> **Advanced / guardrailed pattern.**

**Use when:** clearing cookies client-side isn't enough — you need a reliable global sign-out across
environments and cookie/partition variants (e.g. an embedded or dual-environment app).
**Routes:** `POST /user/logout` → [agents.md](https://agents.1health.io/public/prod/api/user/logout/agents.md) (called server-to-server, per environment)
**Reference code:** [patient-vault `app/api/logout/route.tsx`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/app/api/logout/route.tsx)
**Seen in:** patient-vault-official

## Pattern

A small **stateless** server route (a legitimate second route — it persists nothing):

1. Call the platform's logout endpoint **server-to-server** per environment — a browser call would
   hit CORS/`httpOnly` limits.
2. Emit an expiring `Set-Cookie` for **every** known cookie across each domain/partition variant
   derivable from the request host (so no stale cookie survives).
3. On the client, also sweep `localStorage`, `sessionStorage`, IndexedDB, CacheStorage, and service
   workers for a clean slate.

## Minimal example

```ts
// app/api/logout/route.tsx (sketch)
for (const env of ["demo", "prod"]) {
  const base = baseUrlFor(env)
  await fetch(`${base}/api/user/logout`, { method: "POST", headers: authHeader(env) }).catch(() => {})
}
const res = NextResponse.json({ ok: true })
for (const name of KNOWN_COOKIES) for (const attrs of domainVariants(req))
  res.headers.append("Set-Cookie", `${name}=; Max-Age=0; Path=/${attrs}`)
return res
```

## Gotchas

- Expire each cookie with the **same** attributes (domain, `Partitioned`, `SameSite`) it was set with,
  or the browser keeps it.
- Clear **per-environment** cookie namespaces if you use them (see [iframe-embedding-cookies.md](iframe-embedding-cookies.md)).
- Keep it stateless — this route proxies + clears; it must not persist anything.

## Related

- [setup/auth-and-launch.md](../setup/auth-and-launch.md) · [setup/conventions.md](../setup/conventions.md) §1 (thin proxies)
