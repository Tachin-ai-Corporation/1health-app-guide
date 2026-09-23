# One request funnel: error tiers and a global spinner

**Use when:** you're deciding what happens in the UI when a 1health call fails (or comes back
empty) — and you want one consistent answer app-wide instead of each call site inventing its own
try/catch, plus a loading indicator that doesn't flicker when calls chain back-to-back.
**Routes:** n/a — a cross-cutting wrapper around every call. The Blob/JSON-error gotcha below
applies to any route you call with a binary response type (e.g. a file download).
**Reference code:** [`lib/api/client.ts`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/lib/api/client.ts) — the `ApiResponse` envelope this recipe's tiers wrap.
**Seen in:** every example app (`callApi`'s envelope) · 1health platform usage (the tiered UI
outcome, spinner, and blob-error rehydration below)

## Pattern

1. Put every call through one wrapper (`callApi`/`authFetch`), never a bare `fetch` — uniform
   behavior has to be enforced in one place, not remembered at each call site.
2. Give that wrapper three deliberate error **tiers**, chosen per call rather than left to whatever
   a call site happens to do:
   - **toast-and-swallow (default):** show one generic message, resolve as "no data." Right for an
     ordinary read-and-render where the user can just retry.
   - **silent:** same "resolve empty," no toast. Right when absence is a normal, expected outcome
     (a lookup that legitimately finds nothing) — a toast here would be a false alarm.
   - **rethrow:** no toast; the caller gets the real error. Right whenever a form, wizard, or dialog
     needs to render its own inline error and stay open — a generic toast fires on top of (or
     instead of) the message the form should show.
3. Drive one global loading indicator off a **request counter**, not a per-call boolean: increment
   on start, decrement on settle, and hide only once the counter reaches zero. Debounce the hide
   edge (a few hundred ms) so a burst of back-to-back calls doesn't flicker it on and off.
4. For a transfer large enough that a percentage matters (a big export, an attachment upload), use a
   separate progress-reporting path wired to the browser's upload/download progress events instead
   of the boolean spinner. It only works once the server reports a total size — without one, show an
   indeterminate state, not a percentage frozen at 0%.
5. When a call's response type is binary (`blob`), still sniff the failure body: the platform can
   return a JSON error even though you asked for a blob, and your fetch layer hands back a Blob
   either way. Check the Blob's `type` for a JSON content-type; if it matches, read it as text and
   `JSON.parse` it before treating it as the error — otherwise every download/export failure looks
   like an opaque, message-less blob.
6. Keep a cancelled request out of all of this — see
   [resilient-api-client.md](resilient-api-client.md). It's not a failure, so it shouldn't hit a
   tier, a toast, or the spinner's error path.

## Primary vs fallback

- **Primary — the template's `callApi` `ApiResponse` envelope:** every call site gets back
  `{ success, data?, error?, statusCode? }` and must look at `success` before touching `data` —
  nothing can silently ignore a failure. The tiers above decide what the UI does when `success` is
  `false`; the envelope itself doesn't pick.
- **Fallback — throw-by-default with opt-in silent/swallow tiers:** terser at each call site (no
  `if (!res.success)` boilerplate), but a caller that forgets to catch becomes an unhandled
  rejection instead of a value sitting right there in the response. Only worth it in an app small
  enough to audit every call site for a missing catch.

## Minimal example

```ts
import { callApi, type ApiResponse } from "@/lib/api"

type ErrorTier = "toast" | "silent" | "rethrow"

let inFlight = 0
let hideTimer: ReturnType<typeof setTimeout> | undefined

function spinnerStart() {
  inFlight++
  clearTimeout(hideTimer)
  setGlobalSpinner(true)
}
function spinnerSettle() {
  inFlight = Math.max(0, inFlight - 1)
  if (inFlight === 0) hideTimer = setTimeout(() => setGlobalSpinner(false), 300)
}

/** One funnel: spinner + a chosen error tier, on top of the template's ApiResponse envelope. */
export async function request<T>(
  context: string,
  path: string,
  init: RequestInit = {},
  tier: ErrorTier = "toast",
): Promise<T | undefined> {
  spinnerStart()
  try {
    const res: ApiResponse<T> = await callApi<T>(context, path, init)
    if (res.success) return res.data
    if (tier === "rethrow") throw new Error(res.error)
    if (tier === "toast") showErrorToast(res.error ?? "Something went wrong")
    return undefined // "silent" and "toast" both resolve empty
  } finally {
    spinnerSettle()
  }
}

/** A Blob response can still carry a JSON error body — sniff it before giving up. */
async function readBlobError(response: Response): Promise<string> {
  const blob = await response.blob()
  if (blob.type.includes("json")) {
    const parsed = JSON.parse(await blob.text())
    return parsed.message ?? `Request failed (${response.status})`
  }
  return `Request failed (${response.status})`
}
```

## Gotchas

- Toast-and-swallow and silent-swallow both resolve to `undefined` — a caller expecting a rejected
  promise to `.catch()` will mishandle either unless it explicitly asked for `rethrow`.
- Debounce the spinner's **hide** edge, not its show edge — show it instantly so the UI stays honest
  about a slow call starting; only the hide needs to wait out a possible next call.
- A determinate progress bar needs the server to report a total size; without one, show an
  indeterminate spinner instead of a percentage stuck at 0%.
- The Blob/JSON-error check has to live in the one shared wrapper — leave it to each download call
  site and most won't bother, so their failures render as a useless opaque blob.
- Don't route a cancelled request through any tier — check for your fetch layer's cancellation error
  first and return before the tier logic runs.

## Related

- [resilient-api-client.md](resilient-api-client.md) — the client this wrapper sits on top of
  (single-flight refresh, bare client, cancellation).
- [attachments.md](attachments.md) — a concrete upload/download flow that hits the Blob/JSON-error case.
- [async-trigger-and-poll.md](async-trigger-and-poll.md) and
  [ndjson-progress-streaming.md](ndjson-progress-streaming.md) — other ways to keep a user informed
  during a slow operation.
- Concepts: [../setup/conventions.md](../setup/conventions.md).
