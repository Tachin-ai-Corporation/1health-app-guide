# Capability probe

> **Advanced / guardrailed pattern.**

**Use when:** you're not sure what a given credential (a partner/provider's own token, a scoped API key) actually can and can't do against the platform, and getting it wrong in either direction is expensive — silently over-trusting it is a security hole, silently under-trusting it means routing everything through a privileged key you didn't need.
**Routes:** n/a — this calls whichever real routes you're uncertain about, directly; consult [manifest.md](https://agents.1health.io/public/prod/api/manifest.md) for the full route list to probe against.
**Reference code:** [`components/dev/plane-check.tsx`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/components/dev/plane-check.tsx)
**Seen in:** expertdx

## Pattern

1. Mint a disposable/throwaway record to probe against (never probe with real user data), via your own server, using whatever privileged path already creates one.
2. From the client, call the platform **directly** with the credential under test (e.g. the ordinary user's own token via `authFetch`) — not through your usual server proxy — so you're measuring what the credential itself can do.
3. Write down an **expectation** for each call before running it ("should be allowed" / "should be denied"), not just pass/fail — the interesting failures are on the denied side.
4. Score each result against its expectation and separate the two failure classes: a "should be denied" call that succeeds is a security hole (route everything in that category server-side under a privileged credential); a "should be allowed" call that fails just means that operation needs to be proxied.
5. Make it re-runnable on demand (a button, not a one-off script) — platform permissions change across releases and environments, and this is what catches a regression before a customer does.
6. Gate the tool out of production (dev/staff-only) — it deliberately probes the edges of what a credential can reach, including attempts against another tenant's data.

## Minimal example

```ts
type Expectation = "allowed" | "denied"

async function attempt(name: string, expectation: Expectation, run: () => Promise<Response>) {
  const res = await run().catch(() => null)
  const allowed = !!res?.ok
  const outcome = expectation === "allowed" ? (allowed ? "pass" : "fail") : (allowed ? "fail" : "pass")
  return { name, expectation, status: res?.status ?? "threw", outcome }
}

async function runCapabilityProbe(base: string, probeRecordId: number, foreignRecordId: number) {
  return Promise.all([
    attempt("read my own record", "allowed", () => authFetch(`${base}/api/v2/query`, queryFor(probeRecordId))),
    attempt("submit a workflow step directly", "denied", () => authFetch(`${base}/.../submit`, { method: "POST" })),
    attempt("read another tenant's record", "denied", () => authFetch(`${base}/api/v2/journey/${foreignRecordId}/steps`)),
  ])
  // Any "denied" row whose outcome is "fail" (i.e. it succeeded) is a wall breach: that
  // operation must move behind your own server + a privileged credential.
}
```

## Gotchas

- **A "should be denied" call that succeeds is the finding that matters** — it means your own server routes, not the platform, are the only thing stopping a credential from reaching data it shouldn't.
- **Probe with disposable data, never real records** — this deliberately attempts denied operations, including cross-tenant reads.
- **Re-run per environment** — demo and prod permissions are not guaranteed to match.
- **This is a diagnostic, not a runtime authorization check** — the results tell you which operations to route through a privileged credential (see split-identity-service-key.md); they don't replace server-side authorization on every request.

## Related

- [split-identity-service-key.md](split-identity-service-key.md)
- [server-side-authorization.md](server-side-authorization.md)
- [environment-capability-detection.md](environment-capability-detection.md)
