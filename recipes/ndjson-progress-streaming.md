# NDJSON progress streaming

**Use when:** a single request kicks off several slow, sequential platform calls (a multi-step
provisioning chain, a bulk operation), and a single spinner for ten-plus seconds with no
explanation is exactly the moment people abandon the flow.
**Routes:** n/a — a transport pattern for your own server route (e.g. `POST /api/register/provision`)
**Reference code:** none public — see the Minimal example.
**Seen in:** A specialist-consult ordering app, a transitional-care app

## Pattern

1. Return a `Response` backed by a `ReadableStream` instead of a single JSON body. Set
   `Content-Type: application/x-ndjson` and `Cache-Control: no-store` (and, if your host proxies/
   buffers responses, whatever "don't buffer this" header it supports).
2. Define one small event shape (e.g. `{ step, status, label }`) that your long-running function
   emits via a callback as each stage completes.
3. Encode and enqueue **one JSON object per line** as each event fires. Write a final
   `{ type: "result", ... }` or `{ type: "error", ... }` line, then close the stream.
4. On the client, read the response body as a stream, split on newlines, and parse/render each line
   as it arrives — a simple progress list or log.
5. Let the underlying work **keep running even if the client disconnects** mid-stream. Guard every
   `enqueue` so a write to a closed controller doesn't throw and mask the real error — and don't
   abort work that may have already mutated platform state (an organization may already exist).

## Minimal example

```ts
// Server: a reusable NDJSON response. `work` gets an `emit` that writes one JSON line per call.
function streamNdjson(work: (emit: (line: object) => void) => Promise<void>): Response {
  const utf8 = new TextEncoder()
  let writable = true
  const body = new ReadableStream<Uint8Array>({
    async start(controller) {
      const emit = (line: object) => {
        if (!writable) return
        try {
          controller.enqueue(utf8.encode(JSON.stringify(line) + "\n"))
        } catch {
          writable = false // client disconnected; keep working, stop trying to write
        }
      }
      try {
        await work(emit)
      } finally {
        writable = false
        try { controller.close() } catch { /* the client already closed it */ }
      }
    },
  })
  return new Response(body, { headers: { "Content-Type": "application/x-ndjson", "Cache-Control": "no-store" } })
}

// Server route
export async function POST(request: Request) {
  return streamNdjson(async (emit) => {
    try {
      const result = await runMultiStepProcess((event) => emit({ type: "progress", ...event }))
      emit({ type: "result", result })
    } catch (error) {
      emit({ type: "error", error: error instanceof Error ? error.message : "Failed" })
    }
  })
}

// Client: yield each complete line as a parsed event; a partial line waits for its newline.
async function* ndjsonEvents(stream: ReadableStream<Uint8Array>) {
  const reader = stream.pipeThrough(new TextDecoderStream()).getReader()
  let pending = ""
  for (let chunk = await reader.read(); !chunk.done; chunk = await reader.read()) {
    pending += chunk.value
    for (let nl = pending.indexOf("\n"); nl !== -1; nl = pending.indexOf("\n")) {
      const line = pending.slice(0, nl)
      pending = pending.slice(nl + 1)
      if (line) yield JSON.parse(line)
    }
  }
}

async function provision(body: BodyInit) {
  const res = await fetch("/api/register/provision", { method: "POST", body })
  for await (const event of ndjsonEvents(res.body!)) renderProgress(event)
}
```

## Gotchas

- **A closed/navigated-away client makes every further `enqueue` throw.** Track a `closed` flag and
  swallow post-close writes instead of letting that exception hide the real error in your logs.
- **This is NDJSON — one JSON value per line — not SSE and not a single JSON array.** Don't
  `JSON.parse` the whole body at once on the client; parse line by line as chunks arrive.
- **Streaming responses are sometimes buffered by proxies/hosts by default** — you may need a
  platform-specific header or config to disable buffering, or the client sees nothing until the end.
- **Set a generous max duration for the route.** A multi-call chain — especially if one step itself
  polls — can run well past a typical serverless default timeout.

## Related

- [self-service-org-onboarding-by-npi.md](self-service-org-onboarding-by-npi.md) — the flow this pattern was built for.
- [async-trigger-and-poll.md](async-trigger-and-poll.md) — the complementary pattern when a single step, not a chain, is slow.
