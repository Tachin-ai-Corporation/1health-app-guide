# Write into a closed vocabulary

**Use when:** a write endpoint validates a field against a closed, admin-configured vocabulary (an enum-like value defined server-side, not in your code), and you're writing a value from an external or less-curated source that might not (yet) be recognized.
**Routes:** varies by field — e.g. `POST /api/v2/person/{id}/medical-record` → [manifest](https://agents.1health.io/public/prod/api/manifest.md); the technique applies to any write whose field is validated against a closed vocabulary
**Reference code:** [`lib/api/medical-record.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/api/medical-record.ts#L162) (`parseMissingEvidenceDefinitions`) · [`createMedicalRecord`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/api/medical-record.ts#L309)
**Seen in:** pcp-tcm, expertdx (both attach externally-sourced clinical data through a closed-vocabulary field)

## Pattern

1. A closed-vocabulary field is validated **server-side against a tenant-configured list you don't have locally** — you cannot pre-validate the value; you find out at write time.
2. **Don't guess the accepted set and hardcode it.** Send the value you actually have, and be ready to handle a 400 that names what's wrong.
3. On rejection, **parse the offending value name(s) out of the error body** — these endpoints typically name exactly which value(s) they don't recognize (e.g. `"...names not found: [X, Y]"`).
4. **Strip only the named value(s)** from the payload (drop just that field, or fall back to an untyped/unclassified write) and **retry** — don't drop the whole payload; everything else you were writing is still valid and still worth saving.
5. Bound the retry loop (a rejection can only name each kind of problem once) and stop if a retry's rejection doesn't match anything you can strip — that mismatch is itself worth logging, not looping on.
6. A small known-bad list can skip the guaranteed-to-fail round trip as a fast path, but keep the parse-and-retry as the real safety net — a hardcoded list goes stale the moment the vocabulary changes.

## Minimal example

```ts
import { callApi } from "@/lib/api"

/** The rejected value name(s), parsed from the platform's own error message. */
function parseRejectedValues(detail: string): string[] {
  const match = /names? not found:\s*\[([^\]]*)\]/i.exec(detail)
  if (!match) return []
  return match[1].split(",").map((s) => s.replace(/"/g, "").trim()).filter(Boolean)
}

async function writeWithVocabularyRetry(payload: Record<string, any>, maxAttempts = 3) {
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const res = await callApi("closedVocab/write", "/api/v2/some-write-endpoint", {
      method: "POST",
      body: JSON.stringify(payload),
    })
    if (res.success) return res

    const rejected = parseRejectedValues(res.error ?? "")
    const classificationName = payload.classification?.name
    if (rejected.length === 0 || !classificationName || !rejected.includes(classificationName)) {
      return res // not a vocabulary rejection we can fix — surface the real error
    }

    // Strip exactly the named value; everything else in the payload is kept.
    const { classification, ...rest } = payload
    payload = rest
  }
  return { success: false, error: "Exceeded retry attempts stripping rejected vocabulary values" }
}
```

## Gotchas

- **One unrecognized value 400s the ENTIRE write** on most of these endpoints — there's no "reject just this field, keep the rest." That's exactly why strip-and-retry matters: without it, one bad classification silently loses everything else in the payload.
- Match the retry condition on the **error message content**, not just the HTTP status — a 400 from the same endpoint can also mean "malformed date" or "bad payload shape," and blindly stripping your vocabulary field on those retries forever without fixing anything.
- The classification/type you request is an **ambition, not a requirement** — if the platform doesn't (yet) recognize it, write again without it rather than losing the record; an untyped record still carries all the real data.
- A closed vocabulary differs **per tenant** — a value accepted in one environment can be rejected in another. Never assume staging behavior matches prod.
- Log what you stripped and why (which value, which field) — the real fix is usually "ask the platform admin to add this value," which needs that detail.

## Related

- [read-write-custom-data.md](read-write-custom-data.md) and [write-safety-and-fail-closed.md](write-safety-and-fail-closed.md) — sibling write-robustness patterns.
- [query-the-data-graph.md](query-the-data-graph.md) — reading back what actually landed, to confirm the retried write's shape.
