# Client-side PDF authoring

**Use when:** your intake flow accepts a document in several raw forms (a native file, camera
photos, pasted text) and a downstream step (OCR, an extraction pipeline) works best against one
uniform artifact — normalize them into a single PDF in the browser before upload, rather than
adding a server-side conversion step.
**Routes:** n/a — client helper (produces a `File` that then goes through whichever upload/attach
recipe you're already using — see [patient-documents.md](patient-documents.md) /
[attachments.md](attachments.md)).
**Reference code:** [`components/intake/text-to-pdf.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/components/intake/text-to-pdf.ts) · [`components/mobile/photos-to-pdf.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/components/mobile/photos-to-pdf.ts)
**Seen in:** expertdx

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

## Minimal example

```ts
import { jsPDF } from "jspdf"

const A4_W = 595.28, A4_H = 841.89, MARGIN = 48

// Text -> PDF: wrap, paginate, preserve paragraph breaks.
export function textToPdf(text: string, fileName: string): File {
  const doc = new jsPDF({ unit: "pt", format: "a4" })
  doc.setFont("helvetica", "normal").setFontSize(11)
  const maxWidth = A4_W - MARGIN * 2

  const lines: string[] = []
  for (const para of text.replace(/\r\n/g, "\n").split("\n")) {
    lines.push(...(para.trim() ? (doc.splitTextToSize(para, maxWidth) as string[]) : [""]))
  }
  let y = MARGIN
  for (const line of lines) {
    if (y > A4_H - MARGIN) { doc.addPage(); y = MARGIN }
    if (line) doc.text(line, MARGIN, y)
    y += 15
  }
  return new File([doc.output("blob")], fileName, { type: "application/pdf" })
}

// Photos -> PDF: downscale, one image per page, fit-to-page.
export function photosToPdf(photos: Array<{ dataUrl: string; width: number; height: number }>, fileName: string): File {
  const doc = new jsPDF({ unit: "pt", format: "a4" })
  const maxW = A4_W - MARGIN * 2, maxH = A4_H - MARGIN * 2
  photos.forEach((photo, i) => {
    if (i > 0) doc.addPage()
    const scale = Math.min(maxW / photo.width, maxH / photo.height, 1)
    const w = photo.width * scale, h = photo.height * scale
    doc.addImage(photo.dataUrl, "JPEG", (A4_W - w) / 2, (A4_H - h) / 2, w, h)
  })
  return new File([doc.output("blob")], fileName, { type: "application/pdf" })
}
```

## Gotchas

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
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
