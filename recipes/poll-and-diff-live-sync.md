# Poll-and-diff live sync

**Use when:** several people can act on the same record from different sessions (assign/reassign, a status change) and one viewer's screen needs to reflect another's change without a manual refresh, and there is no webhook/push channel for it.
**Routes:** `GET /api/v2/journey/{id}` → [agents.md](https://agents.1health.io/public/prod/api/v2/journey/_id_/agents.md) — poll it on an interval and diff; project only the fields you need to compare.
**Reference code:** [`hooks/use-assignment-watcher.ts`](https://github.com/Tachin-ai-Corporation/v0-trc-care-coordinator/blob/main/hooks/use-assignment-watcher.ts)
**Seen in:** trc-care-coordinator

## Pattern

1. Poll the **single-record** endpoint on a fixed interval (tens of seconds, not sub-second) — cheap enough to run continuously, unlike a list/grid endpoint.
2. Compute a stable, **order-independent** key from just the fields you care about (e.g. sorted assignee ids) — not the whole payload — so unrelated field churn elsewhere on the record doesn't register as "changed."
3. Compare the new key to the previous one. On a real change: update the displayed data **and** trigger a short-lived visual cue (an animation/flash) so the user notices; on no change, update nothing, so you avoid re-render/animation thrash.
4. Seed the hook's initial state from whatever the parent already has (props from the initial page load) so there's no flash-of-empty before the first poll completes.
5. Guard the interval with an `enabled` flag and always clear it on unmount / when the record id changes — a poll loop that outlives its component is a silent leak and a source of writes to stale state.
6. Derive the comparison key from a **stable primitive**, not raw prop arrays, when the parent passes fresh array references every render — otherwise a naive effect dependency on the arrays re-fires on every parent re-render, not just on real data changes.

## Minimal example

```ts
const POLL_INTERVAL_MS = 30_000

function buildKey(ids: number[]): string {
  return [...ids].sort().join(",")
}

export function useLiveAssignment(recordId: number | undefined, initialAssigneeIds: number[]) {
  const [assigneeIds, setAssigneeIds] = useState(initialAssigneeIds)
  const [justChanged, setJustChanged] = useState(false)
  const prevKey = useRef(buildKey(initialAssigneeIds))

  useEffect(() => {
    if (!recordId) return
    const interval = setInterval(async () => {
      const record = await fetchRecord(recordId)                // GET the single-record endpoint
      const newIds = record.assigneeIds ?? []
      const newKey = buildKey(newIds)
      setAssigneeIds(newIds)
      if (newKey !== prevKey.current) {
        prevKey.current = newKey
        setJustChanged(true)
        setTimeout(() => setJustChanged(false), 3000)
      }
    }, POLL_INTERVAL_MS)
    return () => clearInterval(interval)
  }, [recordId])

  return { assigneeIds, justChanged }
}
```

## Gotchas

- **Diff a derived key, not object identity** — comparing raw arrays/objects "changes" on every poll even when nothing meaningful did, because a fresh array is a new reference every time.
- **Poll the single-record endpoint, not the list/grid** — polling a grid for one record's status is far more expensive and usually cannot be scoped as tightly.
- **Always clear the interval** on unmount and when the identifying id changes, or you accumulate one live poller per record ever viewed in the session.
- **This is a UX nicety, not a consistency guarantee** — between polls the viewer can act on stale data; for anything where that's unsafe, re-check server-side at the point of write instead of trusting the last poll.

## Related

- [async-trigger-and-poll.md](async-trigger-and-poll.md)
- [read-after-write-consistency.md](read-after-write-consistency.md)
- [query-the-data-graph.md](query-the-data-graph.md)
