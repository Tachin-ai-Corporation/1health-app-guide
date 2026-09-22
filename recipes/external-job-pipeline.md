# Third-party job pipeline: submit, poll, persist

**Use when:** a third-party service does slow, asynchronous work (document extraction, AI
inference) via a submit-then-poll API, and its results are only available for a limited window —
you need the result to end up durable in 1health, not lost when the vendor expires it.
**Routes:** n/a — your own server route(s) wrapping a third-party vendor's submit/status/result
endpoints (never expose the vendor's API key to the browser); the eventual persistence step reuses
the routes from [external-record-to-medical-record.md](external-record-to-medical-record.md) /
[read-write-custom-data.md](read-write-custom-data.md).
**Reference code:** [`lib/cqd/client.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/lib/cqd/client.ts) (server-side submit/poll/result) · [`lib/api/cqd.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/api/cqd.ts) (client-side poll loop + persistence)
**Seen in:** expertdx, pcp-tcm

## Pattern

1. **Keep the vendor's API key server-only.** Expose your own thin route(s) for submit/status/
   result; the browser talks only to those, never to the vendor directly.
2. **Make submission idempotent per input.** Key the vendor's job by something stable about the
   input (e.g., the file's own id/hash) so retrying a submit after a dropped response doesn't
   create duplicate jobs for the same document.
3. **Poll on an interval with a hard timeout, and don't let one flaky poll kill the whole wait.**
   Tolerate a handful of consecutive transient failures before giving up; distinguish "still
   running," "genuinely failed," and "timed out" as three different outcomes with three different
   messages, not one generic error.
4. **Treat "succeeded but empty" as its own outcome.** A job can complete with no usable result (an
   unreadable scan, no matches) — that's not a failure to surface as an error, it's a signal to
   fall back to a manual path.
5. **Persist the result into 1health the moment it's available** — don't leave it sitting only in
   the vendor's system or in transient app state. Vendor results are often deleted after a short
   retention window (hours to days); polling to completion and writing into 1health should be one
   continuous flow, not two features you might ship separately.

## Minimal example

```ts
// Client: poll to completion, then persist immediately (never leave the result
// sitting only in the vendor's system — it expires there).
export async function submitAndPersist(file: File, personId: number) {
  const { jobId } = await submitJob(file) // your own /api/<vendor>/ingest route

  const result = await pollToCompletion(jobId)
  if (!result) return { success: false as const, error: "Extraction timed out" }

  // Persist immediately — see external-record-to-medical-record.md for the
  // vendor-shape -> 1health-record translation this calls into.
  return attachExternalRecord(personId, { name: file.name, fileId: await fileIdFor(file), entries: result.entries })
}

async function pollToCompletion(jobId: string, { intervalMs = 2500, timeoutMs = 20 * 60_000 } = {}) {
  const start = Date.now()
  let consecutiveFailures = 0
  while (Date.now() - start < timeoutMs) {
    const job = await fetchJobStatus(jobId) // your own /api/<vendor>/jobs/{id} route
    if (!job) {
      if (++consecutiveFailures >= 3) return null // give up only after repeated failures, not one blip
      await sleep(intervalMs)
      continue
    }
    consecutiveFailures = 0
    if (job.status === "done") return fetchJobResult(jobId) // "done but empty" is still a valid outcome
    if (job.status === "error") throw new Error(job.message ?? "The extractor could not process this document")
    await sleep(intervalMs)
  }
  return null // timed out — distinct from "errored"
}

function sleep(ms: number) { return new Promise((r) => setTimeout(r, ms)) }
```

## Gotchas

- **The vendor's API key is a credential** — hold it only in your server route, never forward it to
  (or accept it from) the browser.
- **Vendor results routinely expire** (observed: as little as 3 days) — persist into 1health as
  soon as the poll succeeds; don't design a flow where a user could plausibly return after the
  window closes and find nothing.
- **A single dropped poll response shouldn't abort the whole wait** — but an unbounded
  retry-forever loop is just a hang with extra steps; cap both the per-poll retry count and the
  overall timeout.
- **"Done" is not the same as "useful"** — a job can complete with an empty result; give the caller
  a distinct signal for that so the UI can offer a manual fallback instead of a generic error.
- **Idempotency is keyed on the input** (the file), not on "did the UI already send this" — a page
  refresh or a double-click shouldn't spawn a second vendor job for the same document.

## Related

- [external-record-to-medical-record.md](external-record-to-medical-record.md) — the usual
  persistence target for the result.
- [deidentify-before-external-ai.md](deidentify-before-external-ai.md) — when the vendor is an AI
  service, gate the outbound side too.
- [client-side-pdf-authoring.md](client-side-pdf-authoring.md) — a common way heterogeneous input
  gets normalized before submission.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
