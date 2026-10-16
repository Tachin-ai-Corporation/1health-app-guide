# Multi-alias payload parsing

**Use when:** you read structured data that several external senders populate independently (different payer feeds, different partner systems) and each one spells its fields differently — one sender's block is `adtMessageData` with `MEMBER_FIRST_NAME`, another's is a shape you have never seen a sample of.
**Routes:** n/a — client-side parsing helper; operates on `customData` already read via `POST /api/v2/query` (see [query-the-data-graph.md](query-the-data-graph.md)).
**Reference code:** none public — see the Minimal example.
**Seen in:** A transitional-care app

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
type Obj = Record<string, any>

/** Case- and separator-blind, so one alias entry covers camelCase, snake_case and kebab-case alike. */
const canonicalKey = (key: string) => key.toLowerCase().split(/[^a-z0-9]+/).join("")

/** Compile an alias list once; the reader returns the value of the first key in `obj` matching any alias. */
function aliasReader(aliases: readonly string[]) {
  const accepted = new Set(aliases.map(canonicalKey))
  return (obj: Obj | undefined): unknown =>
    obj ? Object.entries(obj).find(([key]) => accepted.has(canonicalKey(key)))?.[1] : undefined
}

const readName = aliasReader(["memberFirstName", "MBR_FIRST_NM", "firstName", "FIRST_NM"])
const readStayDate = aliasReader(["admitDate", "ADMT_DT", "dischargeDate", "DSCHRG_DT"])
const readBlock = aliasReader(["payloadData", "payload", "eventData"])

/** A name field AND a stay date — either alone is far too common to be distinctive. */
function looksLikeTargetShape(node: Obj): boolean {
  return readName(node) != null && readStayDate(node) != null
}

const nestedObjects = (node: Obj): Obj[] =>
  Object.values(node).filter((child): child is Obj => !!child && typeof child === "object" && !Array.isArray(child))

/** Find the payload block wherever it is: known key first, then by shape. Breadth-first, bounded. */
function findBlock(customData: Obj, maxDepth = 4, maxNodes = 200): Obj | undefined {
  let visited = 0
  let level: Obj[] = [customData]
  for (let depth = 0; level.length > 0; depth++) {
    const nextLevel: Obj[] = []
    for (const node of level) {
      if (++visited > maxNodes) return undefined
      const block = readBlock(node)
      if (block && typeof block === "object") return block as Obj
      if (looksLikeTargetShape(node)) return node
      if (depth < maxDepth) nextLevel.push(...nestedObjects(node))
    }
    level = nextLevel
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
