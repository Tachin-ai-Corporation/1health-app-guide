# Client-side PDF authoring

**Use when:** your intake flow accepts a document in several raw forms (a native file, camera
photos, pasted text) and a downstream step (OCR, an extraction pipeline) works best against one
uniform artifact — normalize them into a single PDF in the browser before upload, rather than
adding a server-side conversion step. The same client-side-authoring idea also covers producing a
data-driven document (a fax cover sheet, a result letter) by binding a template's placeholders to
your own API response's field paths — see Pattern step 6.
**Routes:** n/a — client helper (produces a `File` that then goes through whichever upload/attach
recipe you're already using — see [patient-documents.md](patient-documents.md) /
[attachments.md](attachments.md)).
**Reference code:** none public — see the Minimal example.
**Seen in:** A specialist-consult ordering app

## Pattern

1. **Give every intake path the same destination shape:** one PDF `File`, regardless of whether the
   source was a dropped file, camera photos, or pasted text. Whatever accepts the "document"
   downstream (an extractor, an attachment endpoint) then has exactly one shape to handle.
2. **For text, wrap to a fixed page size, paginate on overflow, and preserve the input's paragraph
   breaks.** A real text layer (not an image of text) is what most OCR/extraction pipelines read
   most reliably, so prefer composing a text PDF over rasterizing text into an image.
3. **For images, downscale before composing** (cap the longest edge, re-encode at a moderate JPEG
   quality) so a multi-photo capture stays well under your upload size limit, then fit each image
   onto its own page.
4. **Cap input size defensively** (e.g., a max character count for pasted text) and enforce the
   same cap in the UI control that collects it, so the two can't disagree and a mis-paste can't
   produce a runaway document.
5. **Do this entirely client-side** — it's pure transformation with no data to protect and no
   credential involved, so there's no reason to add a server round-trip just to produce a file.
6. **For a data-driven document instead of raw-input normalization**, bind a Handlebars-style
   template's placeholders directly to your own API response's own field paths, and compile it
   with the same call against both a representative sample object (for an offline/live preview)
   and real data (for the live app) — one template, one rendering path, no drift between preview
   and production. Once any version of a template has actually been sent to someone, **version the
   whole template file by date** rather than editing it in place, so a previously sent document's
   exact wording stays reconstructable later.

## Minimal example

```ts
import { jsPDF } from "jspdf"
import Handlebars from "handlebars"

// A4 portrait in PDF points.
const PAGE = { width: 595.28, height: 841.89, margin: 48 }
const BODY = { size: 11, leading: 15 }
const CONTENT = { width: PAGE.width - 2 * PAGE.margin, height: PAGE.height - 2 * PAGE.margin }

const pdfFile = (blob: Blob, name: string) => new File([blob], name, { type: "application/pdf" })

// Text -> PDF: wrap, paginate, preserve paragraph breaks.
export function composeTextDocument(text: string, name: string): File {
  const doc = new jsPDF({ unit: "pt", format: "a4" }).setFont("helvetica", "normal").setFontSize(BODY.size)

  // A blank input line stays a blank output line, so paragraph spacing survives.
  const wrapped: string[] = text
    .split(/\r?\n/)
    .flatMap((para) => (para.trim() ? doc.splitTextToSize(para, CONTENT.width) : [""]))

  const rowsPerPage = Math.floor(CONTENT.height / BODY.leading) + 1
  for (let first = 0; first < wrapped.length; first += rowsPerPage) {
    if (first > 0) doc.addPage()
    wrapped.slice(first, first + rowsPerPage).forEach((row, i) => {
      if (row) doc.text(row, PAGE.margin, PAGE.margin + i * BODY.leading)
    })
  }
  return pdfFile(doc.output("blob"), name)
}

type PageImage = { jpegDataUrl: string; width: number; height: number }

// Shrink to fit the content box (never enlarge), then center on the page.
function placeOnPage({ width, height }: PageImage) {
  const ratio = Math.min(1, CONTENT.width / width, CONTENT.height / height)
  const w = width * ratio, h = height * ratio
  return { x: (PAGE.width - w) / 2, y: (PAGE.height - h) / 2, w, h }
}

// Photos -> PDF: downscale, one image per page, fit-to-page.
export function composePhotoDocument(images: PageImage[], name: string): File {
  const doc = new jsPDF({ unit: "pt", format: "a4" })
  for (const [index, image] of images.entries()) {
    if (index !== 0) doc.addPage()
    const { x, y, w, h } = placeOnPage(image)
    doc.addImage(image.jpegDataUrl, "JPEG", x, y, w, h)
  }
  return pdfFile(doc.output("blob"), name)
}

// A data-driven alternative: bind placeholders to your own API response's field paths, and
// compile the same template against a sample object (preview) or real data (send).
const coverSheetTemplate = `
  Dear {{provider.name}},
  Please find results for {{patient.firstName}} {{patient.lastName}} (DOB {{patient.dob}}) attached.
  {{#if order.testProduct.name}}Test: {{order.testProduct.name}}{{/if}}
`

export function renderCoverSheet(data: Record<string, unknown>): string {
  return Handlebars.compile(coverSheetTemplate)(data) // same call in preview and in the live app
}
```

## Gotchas

- **Once a template version has actually been sent, keep it — don't edit in place.** Save the next
  revision as a new dated file (e.g. `cover-sheet.2026-03-01.ts`) alongside the old one, so a
  previously sent document's exact wording stays reconstructable later.
- **A text layer beats an image of text** for downstream OCR/extraction accuracy — prefer composing
  real PDF text over rendering text to a canvas/image.
- **Downscale photos before composing, not after** — embedding full-resolution camera images
  routinely blows past upload size limits on a multi-page capture.
- **Enforce one size/length cap in both the UI control and the composer function** — if only one of
  them checks, the other path can still produce an oversized document.
- **This produces a `File` in memory; you still need to run it through your normal upload/attach
  call** — this recipe stops at "one normalized document," not "stored somewhere."

## Related

- [patient-documents.md](patient-documents.md) — a typical destination for the produced file.
- [external-job-pipeline.md](external-job-pipeline.md) — the typical next step once the file is
  uploaded.
- [platform-generated-documents.md](platform-generated-documents.md) — when 1health can generate
  the document for you instead of templating it yourself.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
