# Enrich the session inside the token route

**Use when:** you want session context (org id, user id, tenant config) available the instant the
app loads, without adding a second server route or a client round-trip on first paint.
**Routes:** `GET /api/v2/tenant` → [agents.md](https://agents.1health.io/public/prod/api/v2/tenant/agents.md) (called server-side, once, right after token exchange)
**Reference code:** [query-helper `app/api/token/route.tsx`](https://github.com/chill-tachin/v0-1h-query-helper/blob/main/app/api/token/route.tsx)
**Seen in:** v0-1h-query-helper, v0-1health-secure-share, v0-trc-care-coordinator

## Pattern

The `/api/token` route already holds a fresh, valid token for a moment on the server. Use it —
**once** — to seed cheap, stable session ids so the client doesn't have to fetch them before it can
render.

1. Exchange the LPL for OAuth tokens (the normal token-route job).
2. **Before returning,** call `GET /api/v2/tenant` (and/or `/api/v2/user/myself`) server-side with
   that token.
3. Write the derived ids (`user_org_id`, `user_id`) into cookies alongside the auth cookies.
4. The client reads them synchronously (`getOrganizationId()`); no extra fetch on load.

This keeps you at **one** server route — you're enriching the call you already make, not adding a
new one.

## Minimal example

```ts
// inside app/api/token/route.tsx, after you have `access_token` + `baseUrl`
const tenantRes = await fetch(`${baseUrl}/api/v2/tenant`, {
  headers: { Authorization: `Bearer ${access_token}` },
})
if (tenantRes.ok) {
  const tenant = await tenantRes.json()
  const orgId = tenant?.organization?.id
  if (orgId) cookieStore.set("user_org_id", String(orgId), sessionCookieOptions)
}
// ...then set the auth cookies and return as usual
```

## Gotchas

- **Stay at one server route.** This is an add-on to the token exchange, not a general-purpose data
  loader — seed only cheap, stable ids the first screen needs; fetch everything else client-side.
- Cookies the client must read are **not** `httpOnly` (same trade-off as the auth cookies).
- Resolve the correct **per-environment** base URL before the call.
- If the enrichment call fails, don't fail the whole login — set what you can and move on.

## Related

- [setup/auth-and-launch.md](../setup/auth-and-launch.md) — the token route + cookies.
- [setup/conventions.md](../setup/conventions.md) §1 — the one-server-route rule.
