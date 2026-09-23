# Detect environment capabilities

**Use when:** your app runs against multiple 1health environments (sandbox/demo vs. prod, or different tenants) that don't all have the same feature set deployed, and you need to degrade gracefully instead of hard-failing when one is missing.
**Routes:** n/a — a response-interpretation pattern applied to whichever endpoint you call · declared-capability reads use `GET /api/v2/public/tenant/config` → [agents.md](https://agents.1health.io/public/prod/api/v2/public/tenant/config/agents.md) (unauthenticated)
**Reference code:** [`lib/api/client.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/api/client.ts#L51) (`friendlyApiError`)
**Seen in:** patient-vault (typed custom-field APIs deployed in some environments, not yet in others)

## Pattern

1. Some platform capabilities roll out to environments **at different times** — a call that works in one tenant/environment can 404 in another simply because that feature isn't deployed there yet, not because anything is wrong.
2. Recognize the "not deployed" shape specifically instead of treating every non-2xx the same way: a 404 whose body reads like a routing miss (e.g. a generic "no static resource"-style message) generally means the endpoint doesn't exist **here** — as opposed to "this specific record wasn't found."
3. Carry that distinction as a typed flag on your error result (`unavailable: boolean`), not just a status code, so call sites can branch on meaning instead of re-parsing the body themselves.
4. At the call site, treat "unavailable" as a **capability gate**: hide/disable the feature, fall back to an alternative, or show a gentle "not available in this environment yet" message — never a raw stack trace or a generic failure.
5. Re-probe rather than caching "unavailable" forever if your app can move between environments in one session (e.g. switching tenants) — a capability missing in demo can still be present in prod.
6. Run any probe call through a bare, interceptor-free client (see
   [resilient-api-client.md](resilient-api-client.md)) rather than your normal authenticated
   client — a probe's failure is expected and meaningful, and it must never be able to trigger a
   token refresh or logout the way a stray 401 on your main client would.
7. For an **optional** capability that's really a client-side dependency (a third-party script,
   not a 1health route) rather than an environment gap, apply the same tri-state shape but default
   to **fail-open**: if the probe never resolves to "available," drop the dependency from whatever
   it was gating instead of blocking the feature entirely.

## Primary vs fallback

- **Primary — declared flags from the boot config:** read `GET /api/v2/public/tenant/config` once
  at startup (unauthenticated, so it can run before login) and gate routes/sections on the fields
  it returns, kept in shared/reactive state so a tenant switch mid-session re-flows through the
  same gates automatically.
- **Fallback — probe-on-use** (this recipe): reach for it when a capability isn't declared in the
  boot payload at all, or you need finer-grained detection than a tenant-level config object gives
  you (e.g. a specific route's deployment status).

## Minimal example

```ts
import { callApi } from "@/lib/api"

/** True when a 404 means "not deployed here" rather than "record not found". */
function isCapabilityMissing(statusCode: number | undefined, error: string | undefined): boolean {
  return statusCode === 404 && /no static resource/i.test(error ?? "")
}

const res = await callApi<Record<string, unknown>>(
  "customFields/readInstance",
  `/api/v3/custom-data/instance/${personId}`,
)

if (res.success) {
  use(res.data)
} else if (isCapabilityMissing(res.statusCode, res.error)) {
  // This environment doesn't have the feature deployed yet — degrade gracefully.
} else {
  throw new Error(res.error)
}
```

## Gotchas

- Match on the **error body**, not just the status code — a 404 also legitimately means "record not found" elsewhere in the same API, and conflating the two mis-reports real missing data as "feature not deployed."
- This is an environment/deployment gap, not a permissions problem — don't confuse it with a 401/403, which means the caller isn't allowed, not that the feature doesn't exist here.
- Don't hand-maintain a per-environment feature-flag list — probing the actual response is more reliable than tracking "which environments have which features" by hand, since that drifts as the platform ships.
- Surface the gentle message to users; log the technical detail (status + body) for developers — a capability gap is expected and recoverable, not an incident.
- **Don't cache the declared-flags snapshot outside reactive state** — reading it into a local
  variable once means a tenant switch mid-session won't re-flow through the same gates without a
  manual refresh.
- **An optional third-party script that never loads should fail open**, not leave a feature
  permanently disabled — a load that never fires (no error, no success) needs an explicit timeout
  to resolve to "unavailable" too, or the UI just hangs.

## Related

- [resilient-api-client.md](resilient-api-client.md) — the bare-client isolation a probe call should use.
- [typed-custom-field-definitions.md](typed-custom-field-definitions.md) — the concrete API family this was first seen on.
- [read-after-write-consistency.md](read-after-write-consistency.md) — a different "is it there yet" axis (propagation delay vs. deployment gap).
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
