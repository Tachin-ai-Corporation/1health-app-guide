# Log an audit trail in customData

> ⏳ **Watch:** 1health is adding dedicated journey-log APIs. When they ship, prefer them over hand-rolling an audit array in customData; revisit this recipe then.

**Use when:** you need an append-only, attributable history of events on a record (outreach attempts, status changes, corrections) that must never lose history — even once an entry is later found to be wrong.
**Routes:** read via `POST /api/v2/query` (project `customData`) · write via `POST /api/v2/data/custom-data/bulk` → [agents.md](https://agents.1health.io/public/prod/api/v2/data/custom-data/bulk/agents.md)
**Reference code:** [`lib/api/custom-data.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/api/custom-data.ts#L274) (patient notification log)
**Seen in:** pcp-tcm (proof-of-contact outreach log, soft-deleted corrections)

## Pattern

1. Model the log as one `customData` key holding an **array** of entries, each with at least a stable `id`, a timestamp, and whatever else matters (type, outcome, actor).
2. Assign the `id` yourself at write time (a short random/timestamp token) — a JSON array gives its entries no identity of their own.
3. **Appending means read the whole array, push the new entry, write the whole array back.** There's no server-side push operation, and `APPEND` replaces whatever top-level key you send in full (see [read-write-custom-data.md](read-write-custom-data.md)).
4. **Never physically remove or mutate a past entry.** A correction is itself a new fact — mark the entry with a `deleted`/`corrected` sub-object (`{ at, by, reason }`) and keep it in the array. "This was logged, then retracted because X" is exactly what an audit trail is for.
5. Filter soft-deleted entries out client-side wherever you display or count "active" entries, but keep them in every read/write round trip.

## Minimal example

```ts
import { readCustomData, appendCustomData } from "@/lib/api"

const LOG_KEY = "auditLog"

interface AuditEntry {
  id: string
  type: string
  outcome: string
  timestamp: string
  actor?: string
  deleted?: { at: string; by?: string; reason?: string }
}

async function getAuditLog(instanceId: number): Promise<AuditEntry[]> {
  const data = await readCustomData("Organization", instanceId)
  return Array.isArray(data[LOG_KEY]) ? (data[LOG_KEY] as AuditEntry[]) : []
}

/** Append one entry, preserving every prior one. */
async function logAuditEntry(instanceId: number, entry: Omit<AuditEntry, "id">) {
  const existing = await getAuditLog(instanceId)
  const withId: AuditEntry = { ...entry, id: `a-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}` }
  return appendCustomData(instanceId, { [LOG_KEY]: [...existing, withId] })
}

/** Soft-delete: mark an entry retracted, never remove it. */
async function softDeleteAuditEntry(instanceId: number, entryId: string, reason: string) {
  const existing = await getAuditLog(instanceId)
  const log = existing.map((e) =>
    e.id === entryId && !e.deleted ? { ...e, deleted: { at: new Date().toISOString(), reason } } : e,
  )
  return appendCustomData(instanceId, { [LOG_KEY]: log })
}

const activeEntries = (log: AuditEntry[]) => log.filter((e) => !e.deleted)
```

## Gotchas

- There's no push-to-array primitive — every log write is read-the-array → push → write-the-whole-array-back. Two near-simultaneous writers can race and one entry can be lost; acceptable for most audit trails, but don't treat it as a durability guarantee for a compliance-critical count.
- Give every entry a stable `id` at write time — you cannot reliably key a correction off `(timestamp, type)` once two events can share a timestamp.
- Soft-delete only. Physically removing an entry destroys the audit trail's reason for existing — keep it, flagged.
- An array-shaped log grows forever. For high-volume logs, cap/rotate or move to a dedicated store — `customData` isn't a database.

## Related

- [read-write-custom-data.md](read-write-custom-data.md) — the underlying read/`APPEND` mechanics.
- [custom-data-as-state-machine.md](custom-data-as-state-machine.md) — current-state modeling, the complementary pattern to an append-only log.
- [write-safety-and-fail-closed.md](write-safety-and-fail-closed.md) — apply the same fail-closed read before a log append.
