# Survive a hosted-auth redirect with your params intact

**Use when:** you send the user to a 1health-hosted login/registration page (or force a re-login
mid-session) and need more than one thing to come back with them — a deep-link target, a branding
id, a light/dark mode hint — not just a single return-to path.
**Routes:** n/a — a client-side utility around the hosted-auth redirect.
**Reference code:** [`lib/login-intent.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/login-intent.ts) · [`lib/auth-branding.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/auth-branding.ts) — this recipe generalizes both to more than one named param surviving the same hop.
**Seen in:** patient-vault-official (each param individually; see Related)

## Pattern

1. Fix a **named allowlist** of the query params that must survive the bounce — e.g. a deep-link
   target, a branding id, a mode hint. Don't carry the whole query string blindly; an allowlist is
   also your defense against an attacker tacking on an unrelated param.
2. Right before redirecting out, read the current values for those params off the URL and stash
   them in `sessionStorage` under a fixed key — this is **transport across one hop only**, never a
   second source of truth.
3. When building the redirect-out target, **exclude the auth flow's own routes** from anywhere you
   compute "where the user was headed" — a visitor who arrives already mid-flow must not produce a
   redirect that sends them back into the flow again.
4. On the way back, read the stash once, write the values into the **URL** (history-replacing, not
   a new entry), and clear the stash immediately — restoring to the URL, not just memory, is what
   keeps a refresh, a copied link, or a share of the landing page working.
5. Apply the same allowlist-stash-restore mechanism to a **forced re-login** triggered by a session
   revoked mid-use, not just the first sign-in — the source to allowlist-copy from in that case is
   the app's own current URL (it already rendered once with a query string), not a pre-redirect
   stash.
6. Clear the stash on both consumption **and** successful auth completion, so an abandoned
   attempt's leftover values can't resurface on a later, unrelated visit.

## Minimal example

```ts
const SURVIVE_PARAMS = ["openApp", "redirectUri", "brandingId", "mode"] as const
const AUTH_ROUTES = [/^\/login/, /^\/register/, /^\/auth/]
const STASH_KEY = "auth-redirect-params"

function isAuthRoute(path: string): boolean {
  return AUTH_ROUTES.some((re) => re.test(path))
}

/** Call right before redirecting to a hosted login/registration page. */
function stashParamsBeforeRedirect(currentUrl: URL) {
  const picked: Record<string, string> = {}
  for (const key of SURVIVE_PARAMS) {
    const value = currentUrl.searchParams.get(key)
    if (value) picked[key] = value
  }
  if (Object.keys(picked).length) sessionStorage.setItem(STASH_KEY, JSON.stringify(picked))
}

/** Call once, as early as possible, on the page the hosted flow returns to. */
function restoreStashedParams(): void {
  const raw = sessionStorage.getItem(STASH_KEY)
  if (!raw) return
  sessionStorage.removeItem(STASH_KEY) // consume-once, regardless of what happens next

  const url = new URL(window.location.href)
  if (isAuthRoute(url.pathname)) return // never restore back into the auth flow's own pages

  let changed = false
  for (const [key, value] of Object.entries(JSON.parse(raw) as Record<string, string>)) {
    if (!url.searchParams.has(key)) { url.searchParams.set(key, value); changed = true }
  }
  if (changed) window.history.replaceState(null, "", url.toString())
}
```

## Gotchas

- **An allowlist, not the whole query string** — carrying every param blindly re-opens the door
  [return-to-path.md](return-to-path.md)'s open-redirect guard closes.
- **`sessionStorage` is transport, not truth** — the URL is canonical again the moment you're back;
  don't leave a feature reading params only out of the stash.
- **Consume-once, cleared on both paths** — clear the stash when you restore it, and again on
  successful auth, or a stale value from an abandoned attempt resurfaces later.
- **A self-referential redirect is a real bug, not an edge case** — computing "where to send them
  back" from a URL that itself points into the auth flow produces a loop; exclude those routes
  explicitly.
- **A forced mid-session re-login reads from the current URL, not a pre-redirect stash** — the app
  already rendered once before the session was revoked; that rendered URL is your source.

## Related

- [return-to-path.md](return-to-path.md) — the single-opaque-path special case of this idiom.
- [auth-url-branding.md](auth-url-branding.md) — the `brandingId`/`mode` params this idiom is
  commonly used to carry.
- Concepts: [setup/auth-and-launch.md](../setup/auth-and-launch.md)
