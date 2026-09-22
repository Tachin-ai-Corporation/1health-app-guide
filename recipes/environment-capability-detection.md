# Detect environment capabilities

**Use when:** your app runs against multiple 1health environments (sandbox/demo vs. prod, or different tenants) that don't all have the same feature set deployed, and you need to degrade gracefully instead of hard-failing when one is missing.
**Routes:** n/a — a response-interpretation pattern applied to whichever endpoint you call
**Reference code:** [`lib/api/client.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/api/client.ts#L51) (`friendlyApiError`)
**Seen in:** patient-vault (typed custom-field APIs deployed in some environments, not yet in others)

## Pattern

1. Some platform capabilities roll out to environments **at different times** — a call that works in one tenant/environment can 404 in another simply because that feature isn't deployed there yet, not because anything is wrong.
2. Recognize the "not deployed" shape specifically instead of treating every non-2xx the same way: a 404 whose body reads like a routing miss (e.g. a generic "no static resource"-style message) generally means the endpoint doesn't exist **here** — as opposed to "this specific record wasn't found."
3. Carry that distinction as a typed flag on your error result (`unavailable: boolean`), not just a status code, so call sites can branch on meaning instead of re-parsing the body themselves.
4. At the call site, treat "unavailable" as a **capability gate**: hide/disable the feature, fall back to an alternative, or show a gentle "not available in this environment yet" message — never a raw stack trace or a generic failure.
5. Re-probe rather than caching "unavailable" forever if your app can move between environments in one session (e.g. switching tenants) — a capability missing in demo can still be present in prod.

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

## Related

- [typed-custom-field-definitions.md](typed-custom-field-definitions.md) — the concrete API family this was first seen on.
- [read-after-write-consistency.md](read-after-write-consistency.md) — a different "is it there yet" axis (propagation delay vs. deployment gap).
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
