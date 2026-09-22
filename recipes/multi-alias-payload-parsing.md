# Multi-alias payload parsing

**Use when:** you read structured data that several external senders populate independently (different payer feeds, different partner systems) and each one spells its fields differently — one sender's block is `adtMessageData` with `MEMBER_FIRST_NAME`, another's is a shape you have never seen a sample of.
**Routes:** n/a — client-side parsing helper; operates on `customData` already read via `POST /api/v2/query` (see [query-the-data-graph.md](query-the-data-graph.md)).
**Reference code:** [`lib/api/adt-block.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/api/adt-block.ts)
**Seen in:** pcp-tcm

## Pattern

1. For each logical field, list every spelling you have actually seen, with the **known-real spelling first** — the ordering aids readability only; matching itself is a set lookup, not first-match precedence across senders.
2. Normalize keys before comparing: lowercase and strip separators (`_`, `-`) so `adtMessageData`, `adt_message_data`, and `ADT-MESSAGE-DATA` all match one alias entry. This is what keeps the alias lists short enough to maintain.
3. Try the known block/key first; only consult guessed aliases when the known one misses — a wrong guess then costs nothing on the feed that already works.
4. Add a **structural fallback** for the sender nobody has aliased yet: instead of asking "what is this object called," ask "what does it contain" (e.g. "has a name-shaped field AND a stay-date-shaped field"). This is the only check that can succeed against a spelling you've never seen.
5. Choose the structural signal so it's actually distinctive to the shape you're hunting — a single common field (any name, any date) over-matches; require a combination that rules out neighboring shapes (a birth date, for instance, is on every demographic record and should not by itself qualify as a "stay" record).
6. Bound the search (max depth, max nodes visited) — you do not control the shape of an external payload, and an unbounded walk over it is a self-inflicted cost on your own render path.
7. When nothing matches, **report what WAS there, not what you expected** — log the key names (never the values) grouped by sender, so a new spelling becomes a five-minute alias-list fix instead of another round of guessing.

## Minimal example

```ts
function norm(key: string): string {
  return key.toLowerCase().replace(/[^a-z0-9]/g, "")
}

function pick(obj: Record<string, any> | undefined, aliases: readonly string[]): unknown {
  if (!obj) return undefined
  const wanted = new Set(aliases.map(norm))
  for (const [key, value] of Object.entries(obj)) {
    if (wanted.has(norm(key))) return value
  }
  return undefined
}

const NAME_KEYS = ["memberFirstName", "MBR_FIRST_NM", "firstName", "FIRST_NM"] as const
const STAY_DATE_KEYS = ["admitDate", "ADMT_DT", "dischargeDate", "DSCHRG_DT"] as const
const BLOCK_KEYS = ["payloadData", "payload", "eventData"] as const

/** A name field AND a stay date — either alone is far too common to be distinctive. */
function looksLikeTargetShape(node: Record<string, any>): boolean {
  return pick(node, NAME_KEYS) != null && pick(node, STAY_DATE_KEYS) != null
}

/** Find the payload block wherever it is: known key first, then by shape. */
function findBlock(customData: Record<string, any>, maxDepth = 4, maxNodes = 200): Record<string, any> | undefined {
  const queue: Array<{ node: Record<string, any>; depth: number }> = [{ node: customData, depth: 0 }]
  let visited = 0
  while (queue.length && visited < maxNodes) {
    const { node, depth } = queue.shift()!
    visited++
    const hit = pick(node, BLOCK_KEYS)
    if (hit && typeof hit === "object") return hit as Record<string, any>
    if (looksLikeTargetShape(node)) return node
    if (depth >= maxDepth) continue
    for (const v of Object.values(node)) {
      if (v && typeof v === "object" && !Array.isArray(v)) queue.push({ node: v, depth: depth + 1 })
    }
  }
  return undefined
}
```

## Gotchas

- **A single missing alias produces total, silent invisibility for that sender** — not a partial record, not an error, just nothing rendered. Treat "block not found" as loud (logged with key names) rather than a quiet `return null`.
- **Log key names, never values** — the keys are schema and safe to put in a console log; the values are the data you're protecting (often PII/PHI).
- **A weak structural signal over-matches.** Requiring only "has a name field" grabs unrelated objects; require a combination distinctive to the shape you're hunting.
- **Guessed aliases are guesses.** Only the entry confirmed on a live payload is verified — treat the rest as hypotheses to prune or extend once a new sender's real shape is captured.

## Related

- [read-write-custom-data.md](read-write-custom-data.md)
- [fail-closed-dedup-ledger.md](fail-closed-dedup-ledger.md)
- [data-seam-module.md](data-seam-module.md)
