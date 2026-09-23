# Harden your 1health API client

**Use when:** you're writing (or hardening) the fetch wrapper every 1health call goes through, not
just relying on `authFetch`'s proactive refresh — you need it to survive several calls hitting a
`401` at once, calls that must run before a session exists (or must never be able to touch one), a
component that unmounts mid-request, and — if your app can hold more than one tenant's session — a
refresh landing after the user has already switched tenants.
**Routes:** n/a — this hardens the client wiring around every call, not one endpoint. The refresh
call itself is `POST {baseUrl}/auth/oauth2/token`, outside `/api` — see
[setup/auth-and-launch.md](../setup/auth-and-launch.md).
**Reference code:** [`lib/auth-client.ts`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/lib/auth-client.ts) — the proactive-refresh `authFetch` this recipe hardens further.
**Seen in:** every example app (`authFetch`'s proactive refresh) · 1health platform usage (the reactive single-flight refresh, bare wrapper, and tenant pin below)

## Pattern

1. Keep `authFetch`'s proactive refresh — checking expiry before a request avoids most users ever
   seeing a `401`. It doesn't cover everything: token revocation, clock skew between browser and
   server, or a second tab refreshing first can all still hand you a live `401` on a token that
   looked valid a moment ago.
2. Add a **reactive, single-flight refresh** for that case. On the first `401`, start exactly one
   refresh call and hold its promise at module scope; every other call that `401`s while that
   promise is in flight awaits the **same** promise instead of starting its own, then retries with
   whatever token comes out the other end. Three concurrent calls hitting a `401` at once should
   produce one refresh call, not three.
3. If the shared refresh fails, every request waiting on it should fail the same way — don't let a
   fast one retry with a stale token while a slower one gives up.
4. Exclude the refresh call itself from this same `401`-retry path, or a genuinely dead refresh
   token recurses forever.
5. Route calls that run before a session exists, or that must never be able to affect one (a
   branding lookup, a public reference list, any cosmetic pre-login read), through a separate,
   **interceptor-free "bare" wrapper** — no bearer attached, no `401`→refresh→logout handling wired
   up at all, and a short timeout so a slow public call fails fast to a default instead of blocking
   first paint. **Turning credentials off per call on your normal client is not the same thing** —
   its shared `401` handler is still attached and still runs if that "opted-out" call somehow gets a
   stray `401`. Treat any non-success from the bare wrapper (timeout, 404, a disabled flag) the same
   way: fall back to defaults, don't surface an error for a cosmetic read.
6. Cancel with a **per-request `AbortController`** — created by the caller, torn down in its own
   cleanup (an effect unmount, a superseded search) — never a single cancel token shared across
   every in-flight call on an instance, which aborts everything at once. Treat an aborted request as
   an intentional cancel, not a failure: keep it out of whatever generic error tier/toast the rest of
   your call stack uses (see [request-funnel-and-error-tiers.md](request-funnel-and-error-tiers.md)).
7. If your app can hold more than one tenant's session, **pin which tenant a refresh is for** before
   you start it — snapshot the active tenant synchronously, before the `await`. When the refresh
   resolves, check the returned token's own tenant claim against that snapshot; if it names a
   different tenant, treat the refresh as failed and drop it rather than writing a token minted for
   one tenant into another tenant's slot. A tenant switch can land while the refresh is still in
   flight — without this check the mismatch is silent.

## Primary vs fallback

- **Primary — `authFetch` (the template):** proactive refresh plus the hardening above. Do both —
  proactive refresh avoids most users ever eating a `401`'s extra round trip; the reactive half
  covers revocation, clock skew, and concurrent `401`s a proactive check can't predict.
- **Fallback — an axios-style interceptor client:** fine as a drop-in only if it implements the same
  rules — single-flight refresh with shared/queued retries, a genuinely separate bare instance for
  public calls (not a per-call flag), per-request `AbortController`, and the tenant pin if you're
  multi-tenant. An interceptor chain missing any one of these reintroduces the exact failure this
  recipe exists to close.

## Minimal example

```ts
// Additions to lib/auth-client.ts — see setup/auth-and-launch.md for the base authFetch.
import { getOneHealthBaseUrl, getAccessToken, getRefreshToken, SessionExpiredError } from "@/lib/auth-client"

// Reactive, single-flight refresh: every concurrent 401 awaits the SAME promise.
let refreshPromise: Promise<string | null> | null = null

async function refreshOnce(forTenantId: string): Promise<string | null> {
  if (!refreshPromise) {
    refreshPromise = refreshForTenant(forTenantId).finally(() => { refreshPromise = null })
  }
  return refreshPromise
}

async function refreshForTenant(tenantId: string): Promise<string | null> {
  const authRoot = getOneHealthBaseUrl().replace(/\/api\/?$/, "")
  const res = await fetch(`${authRoot}/auth/oauth2/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=refresh_token&refresh_token=${getRefreshToken()}&client_id=public-client`,
  })
  if (!res.ok) return null
  const { access_token, tenant_id } = await res.json()
  if (tenant_id && tenant_id !== tenantId) return null // minted for a DIFFERENT tenant — reject it
  return access_token as string
}

/** Same idea as authFetch, extended with the tenant this call — and its refresh — is pinned to. */
export async function authFetch(url: string, init: RequestInit, activeTenantId: string): Promise<Response> {
  const attempt = (token: string | null) =>
    fetch(url, { ...init, headers: { ...init.headers, Authorization: `Bearer ${token ?? ""}` } })

  const first = await attempt(getAccessToken())
  if (first.status !== 401 || url.includes("/auth/oauth2/token")) return first

  const fresh = await refreshOnce(activeTenantId)
  if (!fresh) throw new SessionExpiredError()
  return attempt(fresh)
}

/** No bearer, no refresh, no logout wiring — safe for public/pre-session reads. */
export async function publicFetch(path: string, init: RequestInit = {}): Promise<Response> {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), 5000) // fail fast; never block first paint
  try {
    return await fetch(`${getOneHealthBaseUrl()}${path}`, { ...init, signal: init.signal ?? controller.signal })
  } finally {
    clearTimeout(timer)
  }
}
```

## Gotchas

- A rejected shared refresh must fail **every** request waiting on it the same way — don't let one
  silently retry with a stale token while another throws.
- Turning off credentials for one call on your normal authed client is not a bare client — the
  shared `401` handler is still wired up and still fires on a stray non-2xx.
- A shared, instance-wide cancel token that aborts every in-flight request at once is legacy
  plumbing — give every request its own `AbortController`.
- Don't feed an aborted request into your generic error toast/report — check for the cancellation
  first and return early.
- If you support tenant switching, pin the tenant **before** the refresh call starts, not after it
  resolves — the switch can land while the request is still in flight.

## Related

- [../setup/auth-and-launch.md](../setup/auth-and-launch.md) — the base `authFetch` flow this hardens.
- [request-funnel-and-error-tiers.md](request-funnel-and-error-tiers.md) — how the rest of the app
  should treat a cancelled or failed call once the client itself is solid.
- [write-safety-and-fail-closed.md](write-safety-and-fail-closed.md) — the same pin-then-verify
  discipline applied to a `customData` write.
- [cross-origin-tenant-switch.md](cross-origin-tenant-switch.md) — the tenant-switch flow the pin
  step above protects.
