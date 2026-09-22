# Handle read-after-write consistency

**Use when:** you write something and then immediately need to read it back (to resolve an id, confirm a value, or feed the next step), and an immediate read can come back stale because the write hasn't fully propagated yet.
**Routes:** n/a — a client-side retry/backoff wrapper around whichever read confirms your write (commonly `POST /api/v2/query`, or a typed-custom-field instance read)
**Reference code:** [`lib/custom-field-resolution.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/custom-field-resolution.ts#L70) (`resolveCustomFieldAfterWrite`)
**Seen in:** patient-vault (resolving a just-defined custom field before it's reliably visible to a read)

## Pattern

1. Don't assume a write is immediately visible to every subsequent read — some paths have measurable propagation lag.
2. Wrap the follow-up read in a **poll-with-backoff**: try immediately, and if the thing you're looking for isn't there yet, wait and try again with increasing delays, up to a bounded number of attempts.
3. Define "found" precisely (a matching id, a field with the expected value) so the loop has an unambiguous stop condition, rather than guessing from a fixed sleep.
4. Return whatever you have when attempts are exhausted — don't throw just because the item hasn't appeared yet — and let the caller decide the fallback (often "let the user retry," since the write itself already succeeded).
5. Make the delay schedule a parameter with a sane default, not a hardcoded sleep, so a fast path and a slow path can share the same helper.

## Minimal example

```ts
/**
 * Poll `read()` until `find()` returns a hit, backing off between attempts.
 * `read` should itself go through `callApi`/`authFetch` like any other call.
 * Never throws just because the item hasn't appeared yet — returns whatever
 * the last attempt produced once attempts are exhausted.
 */
async function pollUntilFound<T, R>(
  read: () => Promise<T>,
  find: (result: T) => R | undefined,
  delaysMs: number[] = [0, 150, 350, 700, 1200],
): Promise<{ result: T; found?: R }> {
  let result!: T
  for (const delay of delaysMs) {
    if (delay > 0) await new Promise((resolve) => setTimeout(resolve, delay))
    result = await read()
    const found = find(result)
    if (found !== undefined) return { result, found }
  }
  return { result, found: undefined }
}

// Example: resolve a field just defined, which may not be visible to the
// very next read.
const { found: field } = await pollUntilFound(
  () => listFieldDefinitions(appId, "Person"),
  (defs) => defs.flatMap((d) => d.fields).find((f) => f.displayName === "Preferred pharmacy"),
)
```

## Gotchas

- Don't loop forever — bound both the attempt count and the total wait; surface a clear "still not visible, try again" outcome rather than hanging the caller.
- This is a workaround for propagation lag, not a substitute for a correct write — if the write itself failed, no amount of polling helps. Check the write's own response first.
- Prefer a short, front-loaded backoff (immediate, then small delays) over one long fixed sleep — most propagation resolves fast, and a fixed multi-second sleep punishes the common case to cover a rare slow one.
- Keep the "found" predicate strict (match the actual value you need, not just "the list is non-empty") — a stale read can return a non-empty but outdated result.

## Related

- [typed-custom-field-definitions.md](typed-custom-field-definitions.md) — the concrete case this pattern was pulled from.
- [environment-capability-detection.md](environment-capability-detection.md) — a different "is it there yet" axis (deployed vs. not, rather than propagated vs. not).
- [write-safety-and-fail-closed.md](write-safety-and-fail-closed.md) — the write-side counterpart: make sure the write itself is trustworthy before you poll for its effects.
