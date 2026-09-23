# Fail-closed writes

**Use when:** you're merging a patch into shared `customData` (or performing any other non-idempotent write), and a failed **read** could otherwise be silently treated as "nothing here yet."
**Routes:** read via `POST /api/v2/query` (project `customData`) · write via `POST /api/v2/data/custom-data/bulk` → [agents.md](https://agents.1health.io/public/prod/api/v2/data/custom-data/bulk/agents.md)
**Reference code:** [`lib/api/custom-data.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/api/custom-data.ts#L217) (`mergeAppScopedData`)
**Seen in:** pcp-tcm (fail-closed retry on the first write after a fresh sign-in)

## Pattern

1. Any "merge a patch into an existing blob" write is a read-modify-write: its correctness depends entirely on the read actually reflecting current state.
2. Treat a **failed or errored read as "unknown," never as "empty."** A ready-made helper that returns `{}` on both "confirmed empty" and "request failed" is not enough here — use the lower-level call and check its own success flag so you can tell the two apart.
3. If you can't confirm what's there, **refuse to write** rather than rebuild the target from just your patch. An empty read masquerading as "nothing there yet" is how existing sibling keys — or another app's namespace — get silently wiped.
4. A fresh session's very first read can lose a race with session/propagation setup and fail transiently. Retry the read once or twice (not a long backoff loop) before giving up — this alone fixes most "it worked the second time" reports.
5. Only proceed to write once the read has succeeded; merge client-side, then write the whole merged object back.
6. For a write that must never double-fire (a real-world side effect — filing a document, sending a notification), keep a small ledger (an id/hash of "already done this") in `customData` and check it in addition to the fail-closed read — and refuse to act when the ledger's state can't be confirmed either.

## Minimal example

```ts
import { runQuery, findAttr, parseCustomData, eq, appendCustomData } from "@/lib/api"

interface WriteResult { success: boolean; error?: string }

/**
 * Merge a patch into a shared customData bucket. Refuses to write when the
 * read can't be confirmed, instead of treating a failed read as "empty".
 *
 * Uses `runQuery` directly (not a `readCustomData`-style helper that returns
 * `{}` on both "confirmed empty" and "read failed") because fail-closed
 * depends on telling those two outcomes apart.
 */
async function mergeSafely(
  type: string,
  instanceId: number,
  patch: Record<string, unknown>,
): Promise<WriteResult> {
  let confirmed: Record<string, unknown> | undefined

  for (let attempt = 0; attempt < 2 && !confirmed; attempt++) {
    const res = await runQuery({ key: type, attributes: ["id", "customData"], filter: eq("id", instanceId), limit: 1 })
    if (res.success) {
      const row = res.data?.data[0]
      confirmed = row ? parseCustomData(findAttr(row, "customData")) : {}
    }
  }

  if (!confirmed) {
    // Never fall through to "assume empty" — that would REPLACE the whole
    // bucket with just `patch`, discarding every sibling key.
    return { success: false, error: "Could not confirm existing data; refusing to write" }
  }

  const res = await appendCustomData(instanceId, { ...confirmed, ...patch })
  return { success: res.success, error: res.success ? undefined : res.error }
}
```

## Gotchas

- "Refuse to write" beats "write something" whenever that something might be an accidental full replace — a raised error is recoverable (retry the click); a silently emptied bucket usually isn't noticed until much later.
- Keep "the read succeeded and found nothing" (genuinely empty — safe to treat as `{}`) and "the read failed" (unknown — must not be treated as `{}`) as two distinct states in your result type; don't let a convenience helper quietly collapse them.
- This composes with the deep-merge helper from [read-write-custom-data.md](read-write-custom-data.md) — fail-closed governs *whether* you write; deep-merge governs *what* you send.
- The platform has no compare-and-set, so fail-closed reduces but doesn't eliminate races between two concurrent writers. Pair it with a rebuildable index ([custom-data-as-state-machine.md](custom-data-as-state-machine.md)) to recover from a lost race, and with a dedup ledger when a write is a real-world action that must not double-fire.
- Log which keys you refused to touch (never their values) when a read fails — it turns a silent data-loss bug into a visible, debuggable one.
- This "confirm the context, refuse on doubt" discipline isn't unique to a `customData` merge — it applies to any async operation whose correctness depends on a context a concurrent action could change out from under it. A token refresh racing a tenant switch is the same shape: pin which tenant the refresh is *for* before the call, and treat a returned token claiming a different tenant as a failed refresh, not a result to store (see [resilient-api-client.md](resilient-api-client.md)).

## Related

- [read-write-custom-data.md](read-write-custom-data.md) — the deep-merge mechanics this pattern wraps with a safety check.
- [custom-data-as-state-machine.md](custom-data-as-state-machine.md) — recovering a cache via rebuild when a race still slips through.
- [read-after-write-consistency.md](read-after-write-consistency.md) — the companion problem: your write succeeded, but a read right after doesn't see it yet.
- [resilient-api-client.md](resilient-api-client.md) — the same pin-then-verify discipline applied to a token refresh racing a tenant switch.
