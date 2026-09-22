# Fail-closed dedup ledger

**Use when:** you must perform a non-idempotent write (attach a document, file a chart entry, create a downstream record) from an automated or repeatable trigger, and writing it twice is worse than occasionally not writing it at all.
**Routes:** read via `POST /api/v2/query` (project `customData`) · write via `POST /api/v2/data/custom-data/bulk` → [agents.md](https://agents.1health.io/public/prod/api/v2/data/custom-data/bulk/agents.md)
**Reference code:** [`lib/partner-records/ledger.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/partner-records/ledger.ts), [`lib/partner-records/filing.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/partner-records/filing.ts#L636)
**Seen in:** pcp-tcm

## Pattern

1. Before any write that cannot be undone or safely repeated, ask two questions in order: "have **we** already done this?" (a ledger you control) and, only if needed, "does the target already show it?" (a read of the record itself). Ask the ledger first — it does not depend on correctly parsing a foreign response shape.
2. Keep the ledger as its own `customData` entry on a durable, appropriately-scoped instance (e.g. the `Organization`, so the guard applies once per practice, not once per browser), namespaced under your app, keyed by whatever idempotency key identifies the source event (a source-record id, a job id).
3. **Fail closed on every read.** If the ledger cannot be read, or the target record's readability cannot be positively confirmed, **throw** — never treat an unreadable response the same as an empty one. An empty list and a broken parser look identical from the caller's side, but only one of them means "safe to write."
4. Positively evidence a successful read before trusting "not found." A `200` response is not proof the read succeeded — confirm the response actually carries the attribute/relationship you're checking (e.g. the expected attribute key is present in at least one row) before concluding the target has nothing yet.
5. Perform the write, then record it in the ledger **immediately after**, before reporting success to the caller — so a crash between the write and the ledger update is the only remaining duplicate window, and it's the one a secondary record-level check can still catch.
6. Serialize ledger writes with a simple promise chain (or equivalent) when the same key can be written concurrently — a naive read-modify-write over one shared blob drops whichever write lands second.
7. Cap and trim the ledger (oldest-first) so a long-lived app cannot grow it without bound; an entry falling off only means the read-based guard has to answer for that record again — the normal, safe path, not a regression.

## Minimal example

```ts
import { readCustomData, mergeCustomData, appData } from "@/lib/api"

const LEDGER_KEY = "recordsFiled"
type Ledger = Record<string, { targetId: number; at: string }>

async function loadLedger(ownerType: string, ownerId: number, appId: string): Promise<Ledger> {
  try {
    const data = await readCustomData(ownerType, ownerId)
    return ((data.appData as any)?.[appId]?.[LEDGER_KEY] as Ledger) ?? {}
  } catch (error) {
    // An unreadable ledger must NOT look like an empty one.
    throw new Error(`Could not read the ledger, so nothing was written: ${error}`)
  }
}

let writeChain: Promise<unknown> = Promise.resolve()

function recordDone(ownerType: string, ownerId: number, appId: string, sourceKey: string, targetId: number) {
  writeChain = writeChain.then(async () => {
    const ledger = await loadLedger(ownerType, ownerId, appId).catch(() => ({}) as Ledger)
    const next = { ...ledger, [sourceKey]: { targetId, at: new Date().toISOString() } }
    await mergeCustomData(ownerType, ownerId, appData(appId, { [LEDGER_KEY]: next }))
  })
  return writeChain
}

/** The guard, called before the irreversible write. */
export async function writeOnce(
  ownerType: string, ownerId: number, appId: string, sourceKey: string, doWrite: () => Promise<number>,
) {
  const ledger = await loadLedger(ownerType, ownerId, appId)          // throws if unreadable — refuses to proceed
  if (ledger[sourceKey]) return { status: "already-done" as const, targetId: ledger[sourceKey].targetId }

  const targetId = await doWrite()
  await recordDone(ownerType, ownerId, appId, sourceKey, targetId)    // note it BEFORE returning success
  return { status: "done" as const, targetId }
}
```

## Gotchas

- **An empty result and a broken parser are indistinguishable to the caller.** The failure mode this pattern exists to prevent is exactly this: a `/query` answered `200` with a shape a parser didn't recognize, zero rows came back, and zero rows read as "nothing filed yet" — so an automated trigger refiled the same record on every run. Positively confirm the read succeeded; never infer "empty" from "I found nothing."
- **The ledger is best-effort on write, fail-closed on read.** A failed ledger *write* only risks a duplicate on the next run, which the read-side check can still catch. A failed ledger *read* must abort the write entirely.
- **Prefer two independent signals when you can afford it** — a ledger entry AND a deterministic fingerprint embedded in the created record (a name, a marker) — because a platform that renames, truncates, or reshapes a field can silently defeat one signal without you noticing, and the second one still catches it.
- **Never log the values you are deduping on if they carry PII/PHI** — log key names, counts, and ids, never content, so the diagnostics that make this debuggable don't become a new data leak.

## Related

- [read-write-custom-data.md](read-write-custom-data.md)
- [write-safety-and-fail-closed.md](write-safety-and-fail-closed.md)
- [multi-alias-payload-parsing.md](multi-alias-payload-parsing.md)
- [data-seam-module.md](data-seam-module.md)
