# Sanitizing BFF proxy

**Use when:** you need to expose one sensitive or awkward upstream 1health call to the browser through your own server route — to keep the session token server-side, normalize an inconsistent response shape, or avoid leaking raw upstream error text — without turning that route into a second datastore.
**Routes:** n/a — client-facing helper route; the example wraps `GET/PUT /api/v2/agreement/_type_[/accept]` (see [baa-gating.md](baa-gating.md) for that route's own contract)
**Reference code:** [`app/api/agreements/baa/route.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/app/api/agreements/baa/route.ts) · [`lib/baa-agreements.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/baa-agreements.ts)
**Seen in:** patient-vault

## Pattern

1. Keep the route **stateless**: every call re-reads/re-writes 1health and returns; nothing here becomes a second source of truth. (Contrast the anti-pattern of a server route backed by its own database.)
2. **Normalize** the upstream shape once, in a small pure function, before it reaches the client — e.g. collapse an array of agreement rows into `{ accepted, pendingIds }`. Validate defensively: return `null` (and a 502) on a shape you don't recognize, rather than passing malformed data through.
3. **Rewrite error text** for anything the end user might see — map known upstream statuses/messages to a specific, safe string, with one generic fallback for anything unrecognized. Never forward a raw upstream error body to the browser.
4. Keep the session token **server-side only**: read it from an httpOnly cookie and attach it to the upstream call yourself; the browser never sees it.
5. Mark the response `no-store` — it's a live reflection of platform state (an acceptance flag someone else could change), not something to cache.

## Minimal example

```ts
import { cookies } from "next/headers"
import { NextResponse } from "next/server"

const AGREEMENT_PATH = "/api/v2/agreement/BAA%20Organization%20Standard"

function noStore(body: unknown, status = 200) {
  return NextResponse.json(body, { status, headers: { "Cache-Control": "no-store" } })
}

// Normalize the upstream shape into exactly what the UI needs — nothing more.
function normalize(raw: unknown): { accepted: boolean; pendingIds: number[] } | null {
  if (!Array.isArray(raw) || raw.length === 0) return null
  const rows = raw.map((r) => ({ id: r?.id, accepted: r?.state?.accepted === true }))
  if (rows.some((r) => typeof r.id !== "number")) return null
  return { accepted: rows.every((r) => r.accepted), pendingIds: rows.filter((r) => !r.accepted).map((r) => r.id) }
}

// Map known upstream failures to safe, specific copy; never forward raw error text.
async function safeUpstreamError(response: Response): Promise<string> {
  if (response.status === 401 || response.status === 403) return "Your session is not authorized to view this."
  return "The service is temporarily unavailable. Please try again."
}

export async function GET() {
  const token = (await cookies()).get("access_token")?.value
  if (!token) return noStore({ error: "Sign-in required." }, 401)

  const response = await fetch(`${process.env.ONEHEALTH_BASE_URL}${AGREEMENT_PATH}`, {
    headers: { Authorization: `Bearer ${token}` },
    cache: "no-store",
  })
  if (!response.ok) return noStore({ error: await safeUpstreamError(response) }, response.status)

  const status = normalize(await response.json())
  if (!status) return noStore({ error: "Unexpected response shape." }, 502)
  return noStore(status)
}
```

## Gotchas

- This is a proxy, not a datastore — resist caching or persisting anything here; that's the line between "thin stateless proxy" (fine) and a second backend (not).
- Validate the upstream shape defensively and fail with a clear 502 rather than passing a malformed/partial object through — a client trusting an unnormalized shape breaks differently on every upstream change.
- A server route legitimately uses plain `fetch` with a manually-attached Bearer header here — it already holds the raw token from an httpOnly cookie; `authFetch`'s browser-side refresh logic isn't what this boundary needs.
- "Rewriting errors" means picking specific, safe messages for failure modes you actually know about plus one generic fallback — not echoing `response.text()` from upstream, which can leak internal detail.
- `no-store` matters specifically because the answer reflects live platform state that can change from other surfaces (e.g. someone else accepting the same agreement directly).

## Related

- [baa-gating.md](baa-gating.md) — the underlying agreement pattern this proxy wraps.
- [baa-status-split-identity.md](baa-status-split-identity.md) — a related BAA pattern using a different identity, not a proxy.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md), [setup/conventions.md](../setup/conventions.md).
