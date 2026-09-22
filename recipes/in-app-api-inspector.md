# In-app API inspector

> **Advanced / guardrailed pattern.**

**Use when:** you want a devtool panel that shows every real API call your app just made (method, path, status, body) without threading a logging call through every call site, in a codebase where the HTTP helper is a plain module and the panel is a React tree.
**Routes:** n/a — wraps your existing `authFetch` calls; makes none of its own.
**Reference code:** [`lib/api-inspector-bus.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/api-inspector-bus.ts)
**Seen in:** patient-vault

## Pattern

1. Put a tiny, dependency-free pub/sub bus in its own module, imported by **both** your HTTP helper and your React devtool panel — kept free of imports from either side, which is what avoids a cycle between a plain HTTP module and a React context that (transitively) imports it.
2. Have the HTTP helper (your `authFetch` wrapper) publish one event per real round-trip — method, path, request/response bodies, status, latency — right where it already has all of that in scope.
3. Have the devtool panel subscribe on mount and append to a bounded in-memory list; nothing here is persisted.
4. Buffer events published before any subscriber has mounted (app boot fires calls before the panel exists), capped, and flush the buffer to the first subscriber.
5. Truncate large fields (a base64 upload payload) **at publish time** — prefix + size annotation — so the full payload is never retained downstream, including in the buffer.

## Minimal example

```ts
// api-call-bus.ts — no imports from either side; breaks the cycle between them.
type Call = { method: string; path: string; status: number; requestBody?: unknown; responseBody?: unknown; latencyMs: number }
const listeners = new Set<(call: Call) => void>()
let buffer: Call[] = []
const MAX_BUFFER = 200

export function publishApiCall(call: Call): void {
  if (listeners.size === 0) {
    buffer.push(call)
    if (buffer.length > MAX_BUFFER) buffer = buffer.slice(-MAX_BUFFER)
    return
  }
  for (const fn of listeners) fn(call)
}

export function subscribeApiCalls(fn: (call: Call) => void): () => void {
  listeners.add(fn)
  if (buffer.length) { const pending = buffer; buffer = []; pending.forEach(fn) }
  return () => listeners.delete(fn)
}

// inside your authFetch wrapper, once the real response comes back:
publishApiCall({ method, path, status: res.status, requestBody, responseBody, latencyMs: Date.now() - start })
```

## Gotchas

- **Never log full upload payloads (base64 files, tokens)** — truncate at publish time, or the full value sits in memory regardless of whether anyone opens the panel.
- **This mirrors real traffic only if wired into the actual fetch wrapper** — hand-written illustrative entries will drift from what the app actually sends.
- **Gate this out of production** if requests can carry PHI/secrets — an in-memory devtool panel is still visible to a screenshare or browser extension.

## Related

- [capability-probe.md](capability-probe.md)
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
