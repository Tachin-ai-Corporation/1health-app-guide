# Cookies for an embedded (iframed) app

**Use when:** your app is launched **inside a cross-site iframe** (e.g. embedded in the 1health
portal) and the session silently fails — cookies set on your origin aren't sent back in the
third-party context.
**Routes:** n/a — cookie attributes on the `/api/token` `Set-Cookie` and any client-set cookies.
**Reference code:** [pcp-tcm `lib/auth-client.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/auth-client.ts) · [patient-vault `lib/auth-client.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/auth-client.ts)
**Seen in:** v0-1health-pcp-transitional-care-management, patient-vault-official

## Pattern

A cookie is only sent inside a cross-site iframe if it is `SameSite=None; Secure`, and modern
browsers additionally require **`Partitioned`** (CHIPS) so the cookie is scoped to the embedding
site. Apply this to **every** session cookie — both the ones `/api/token` sets and any the client
writes on refresh.

1. On **HTTPS**, set session cookies with `SameSite=None; Secure; Partitioned`.
2. On plain **HTTP** (local dev only), fall back to `SameSite=Lax` (None+Secure won't stick).
3. Use the same attributes everywhere a cookie is set, updated, or expired.

## Minimal example

```ts
function cookieAttributes(): string {
  const https = typeof window !== "undefined" && window.location.protocol === "https:"
  return https ? "; SameSite=None; Secure; Partitioned" : "; SameSite=Lax"
}
document.cookie = `access_token=${encodeURIComponent(token)}; Path=/; Max-Age=${maxAge}${cookieAttributes()}`
```

## Gotchas

- `SameSite=None` **requires** `Secure` — so it only works over HTTPS; test embedding on a real
  https origin, not localhost.
- Without `Partitioned`, CHIPS-enforcing browsers still drop the cookie in the iframe.
- These cookies are intentionally **not** `httpOnly` (the client needs them for `authFetch`) — an
  inherent XSS trade-off of the client-side call model; keep that in mind for a high-sensitivity app.
- Verify inside the **actual** iframe/portal, not a standalone tab — the failure only appears in the
  embedded context.

## Related

- [setup/auth-and-launch.md](../setup/auth-and-launch.md) — cookies the launch flow sets.
- [enrich-session-in-token-route.md](enrich-session-in-token-route.md)
