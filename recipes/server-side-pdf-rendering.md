# Render a PDF server-side

**Use when:** you must hand back a PDF that carries a fact only the server can vouch for — an
acceptance stamp, a computed overlay — or you must produce one with no browser present. (If you're
just letting someone save what's already on their own screen, see the last Gotcha — a client-side
print often beats this.)
**Routes:** composes existing reads, e.g. `GET /api/v2/agreement/{type}` → [agents.md](https://agents.1health.io/public/prod/api/v2/agreement/agents.md) and `GET /api/v2/file/{id}/download` → [route docs](https://agents.1health.io/public/prod/api/manifest.md); the render/stamp step itself is local, not a 1health call.
**Reference code:** [`lib/baa-stamp.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/baa-stamp.ts#L150) · [`app/api/baa/stamped/route.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/app/api/baa/stamped/route.ts#L29)
**Seen in:** pcp-tcm (acceptance stamp on a legal agreement)

> **Try 1health's own document generation first.** For a lab requisition, test-result report, or
> branded requisition, 1health generates the PDF for you — see
> [platform-generated-documents.md](platform-generated-documents.md). Reach for this recipe's own
> compositing approach only for document kinds the platform doesn't already generate — like the
> stamped-agreement example below.

## Pattern

1. **Identify what must be true on the PDF that the client must not get to assert** — an acceptance
   date, a signatory, a computed total. If a client-supplied value could end up on the document, the
   document proves nothing.
2. **Re-fetch those facts server-side, at request time**, through the caller's own token — never
   accept them as request parameters. A route that stamped a client-supplied date would let anyone
   mint a PDF asserting someone signed something.
3. **Fetch the source file's bytes server-side too** (by id, with a public-URL fallback if the
   platform offers one), through the same token, so 1health's own authorization still governs who
   can read the underlying document.
4. **Render/overlay with a server-only PDF library** (e.g. `pdf-lib`). Guard the module so no client
   component can import it — these libraries are heavy and assume Node APIs the browser bundle
   shouldn't carry.
5. **Stream the bytes back directly** from the route with the right `Content-Type`, choosing
   `inline` vs. `attachment` off a query flag rather than two routes, and mark the response
   `Cache-Control: private` since the output is personalized.
6. **Fail soft.** If the stamping step throws, serve the original, unstamped bytes rather than a
   500 — the reader asked for the document, and an unstamped copy beats none.

## Minimal example

```ts
// lib/document-stamp.ts — server-only
import "server-only"
import { PDFDocument, StandardFonts } from "pdf-lib"

export async function stampDocument(
  bytes: ArrayBuffer,
  facts: { acceptedAt: string | null; signatoryName: string | null },
): Promise<Uint8Array> {
  if (!facts.acceptedAt && !facts.signatoryName) return new Uint8Array(bytes)
  const doc = await PDFDocument.load(bytes)
  const font = await doc.embedFont(StandardFonts.HelveticaBold)
  for (const page of doc.getPages()) {
    page.drawText(`Accepted ${facts.acceptedAt ?? ""} — ${facts.signatoryName ?? ""}`, {
      x: 24, y: page.getHeight() - 24, size: 10, font,
    })
  }
  return doc.save()
}

// app/api/agreement/stamped/route.ts
export async function GET() {
  const token = /* the caller's own access token, read from an httpOnly cookie */ ""
  const baseUrl = /* resolved per call — see rules-of-the-road.md */ ""

  const agreement = await fetch(`${baseUrl}/api/v2/agreement/${AGREEMENT_TYPE}`, {
    headers: { Authorization: `Bearer ${token}` },
  }).then((r) => r.json())

  const original = await fetch(`${baseUrl}/api/v2/file/${agreement.content.id}/download`, {
    headers: { Authorization: `Bearer ${token}` },
  }).then((r) => r.arrayBuffer())

  let body: Uint8Array
  try {
    body = await stampDocument(original, {
      acceptedAt: agreement.state?.actionPerformedAt ?? null,
      signatoryName: agreement.state?.signatory?.firstName ?? null,
    })
  } catch {
    body = new Uint8Array(original) // fail soft: unstamped beats nothing
  }

  return new Response(body, {
    headers: { "Content-Type": "application/pdf", "Cache-Control": "private, max-age=300" },
  })
}
```

## Gotchas

- **Never take the stamped fact from the request** — re-derive it from 1health on every call, or the
  PDF only asserts what the caller typed.
- **Keep the PDF library server-only.** It's dead weight in a client bundle and has no reason to run
  in the browser.
- **Fail soft toward the unstamped original** rather than a hard error — the underlying document is
  still what the reader asked for.
- **This is for compositing onto an existing document, or rendering with no browser present.** If you
  only need to let a user save what's already on screen, a client-side `window.print()` with print
  CSS can beat client-side canvas rasterization — real selectable text, no server round trip. Reserve
  the server path for facts the client shouldn't be trusted to assert.

## Related

- [platform-generated-documents.md](platform-generated-documents.md) — the primary path for
  requisition/result/branded-requisition PDFs; try it before reaching for this recipe.
- [baa-gating.md](baa-gating.md) — the agreement-acceptance flow this often stamps.
- [read-write-custom-data.md](read-write-custom-data.md) · [../setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
