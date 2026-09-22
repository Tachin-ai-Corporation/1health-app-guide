# Proxy a public reference API

**Use when:** your app needs data from a public, unauthenticated reference API (an NPI directory,
an ICD-10 lookup, a drug database) that either blocks CORS from the browser or you simply don't
want to call directly from the client — and the result is reference data, not something you need
1health to persist as application state.
**Routes:** n/a — this is a route **you** define (e.g. `GET /api/<your-proxy>/[param]`), not a
1health endpoint. It sits alongside `/api/token` as one of the narrow, stateless exceptions to
"the client calls 1health directly."
**Reference code:** [`app/api/npi/lookup/route.ts`](https://github.com/Tachin-ai-Corporation/v0-trc-care-coordinator/blob/main/app/api/npi/lookup/route.ts) · [`app/api/npi-lookup/route.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-med-adherence-bcbsm/blob/main/app/api/npi-lookup/route.ts) · [`lib/npi/registry.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/npi/registry.ts) · [`app/api/icd10/[code]/route.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/app/api/icd10/%5Bcode%5D/route.ts)
**Seen in:** trc-care-coordinator, med-adherence, pcp-tcm

## Pattern

1. **Write one thin server route per external reference source**, whose only job is to forward the
   request server-side (where CORS doesn't apply) and reshape the response into whatever your UI
   wants. It holds no 1health credential and persists nothing — a pass-through, not a datastore.
2. **Validate/normalize the input before forwarding** (strip non-digits from an NPI, checksum-
   validate it) so a bad request fails fast with a clear error instead of a confusing upstream 4xx.
3. **Degrade gracefully.** A public reference API you don't control can be slow, down, or return an
   unexpected shape — set a request timeout, catch every failure mode, and return a typed "not
   found"/"unavailable" result rather than letting the error bubble up raw or hang the caller.
4. **Cache what's safe to cache.** Reference data like an ICD-10 description or an NPI record
   changes rarely — set a long `Cache-Control`/revalidate window on your route, and/or dedupe
   concurrent in-flight lookups for the same key with an in-memory promise map.
5. **Keep the response shape yours, not the vendor's.** Reshape the upstream payload into a small,
   stable DTO your app controls, so a vendor schema change is a one-file fix, not a hunt through
   every call site.

## Minimal example

```ts
// app/api/reference/[code]/route.ts — your own server route, not a 1health one.
import { NextRequest, NextResponse } from "next/server"

export async function GET(_req: NextRequest, { params }: { params: Promise<{ code: string }> }) {
  const { code: raw } = await params
  const code = (raw || "").replace(/[^a-z0-9]/gi, "").toUpperCase()
  const fallback = NextResponse.json({ code, description: code }, { headers: { "Cache-Control": "public, max-age=86400" } })
  if (!code) return fallback

  try {
    const res = await fetch(`https://public-reference-api.example.gov/lookup?code=${encodeURIComponent(code)}`, {
      signal: AbortSignal.timeout(5000),
    })
    if (!res.ok) return fallback // degrade to the code itself rather than erroring
    const data = await res.json().catch(() => null)
    return NextResponse.json(
      { code, description: data?.description ?? code },
      { headers: { "Cache-Control": "public, max-age=86400" } },
    )
  } catch {
    return fallback
  }
}
```

```ts
// Client: dedupe concurrent lookups for the same key.
const inFlight = new Map<string, Promise<{ code: string; description: string }>>()
export function lookupReference(code: string) {
  if (!inFlight.has(code)) {
    inFlight.set(code, fetch(`/api/reference/${code}`).then((r) => r.json()).finally(() => inFlight.delete(code)))
  }
  return inFlight.get(code)!
}
```

## Gotchas

- **This route is a deliberate, narrow exception to "call 1health directly from the client"** —
  keep it stateless (no writes to any datastore) or it stops being the thin proxy the rule allows.
- **Always return a usable fallback** (the input code, an "unavailable" flag) rather than a 500 — a
  reference lookup failing shouldn't block the feature it's decorating.
- **Set an explicit fetch timeout** — a public government/vendor API with no SLA can hang far
  longer than your route's own timeout budget.
- **A missing/zero-result response from the upstream is not an error** — model "not found" as its
  own outcome, not a caught exception.

## Related

- [cache-reference-data-in-custom-data.md](cache-reference-data-in-custom-data.md) — avoid re-hitting
  this proxy for data you've already resolved once.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
