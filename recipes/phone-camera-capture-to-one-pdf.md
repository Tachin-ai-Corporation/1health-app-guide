# Capture paper records with a phone camera, as one PDF on the record

**Use when:** a signed-in desktop user needs to add paper records to a case or journey step, using
a phone as the camera, without signing in again on the phone. Also whenever a user adds several
photos at once on any upload screen.
**Routes:** `POST /api/v2/health/type/{typeKey}/{instanceId}/relation/{relKey}/file/upload?fileName=…&isPublic=false` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/type/_typeKey_/_instanceId_/relation/_relKey_/file/upload/agents.md) (the PDF as a step attachment: `typeKey` = `WorkflowTemplateStep`, `relKey` = `WorkflowTemplateStepHasAttachmentFile`) · `POST /api/v2/data/custom-data/bulk` → [agents.md](https://agents.1health.io/public/prod/api/v2/data/custom-data/bulk/agents.md) (the one-time hand-off ticket — see [qr-device-session-handoff.md](qr-device-session-handoff.md)) · optional: `POST /api/v2/twilio/send` → [agents.md](https://agents.1health.io/public/prod/api/v2/twilio/send/agents.md) (`{ toPhoneNumber, text }`, to text the link instead of showing a QR)
**Reference code:** none public — see the Minimal example.
**Seen in:** A specialist-consult ordering app

## Pattern

1. **Offer one link two ways.** On the desktop, show the capture link as a QR code, or text it to
   the user's *verified* mobile (see [add-a-phone-for-mfa.md](add-a-phone-for-mfa.md)). Mint it with
   one function for both — they differ only in delivery, never in how the session is sealed. Mint
   and seal as in [qr-device-session-handoff.md](qr-device-session-handoff.md). Render the QR
   server-side as a PNG data URL: black on white, with a quiet zone and error-correction level M.
2. **Opening the link only peeks.** Loading the page (a GET) never redeems anything: it asks your
   server whether the ticket is still valid and for a non-sensitive label, such as the case
   reference. The ticket is redeemed and burned only by a POST from an explicit "Start" tap.
3. **Capture with the live camera.** Use the rear camera through
   `getUserMedia({ video: { facingMode: { ideal: "environment" } } })` and a shutter button. Each tap
   grabs the current frame as a downscaled JPEG (e.g. 1600 px longest edge, quality about 0.72). Show
   thumbnails with retake and remove. Fall back to
   `<input type="file" accept="image/*" capture="environment">` when `getUserMedia` is missing or
   denied.
4. **On Done, upload one PDF.** Compose every page into **one PDF** in the browser
   ([client-side-pdf-authoring.md](client-side-pdf-authoring.md)) and check its size against your
   upload cap. Upload it **once** to the step's attachment relation, under the user's own identity.
   Then record it server-side in your app's manifest — after checking that the file id really is on
   that record, never trusting a client-supplied id.
5. **The phone only captures.** After the upload it says "Finish on your desktop." The desktop
   picks up the new file ([poll-and-diff-live-sync.md](poll-and-diff-live-sync.md)) and runs any
   reading or extraction there, once.
6. **End the phone session.** Offer "I'm done" to clear the session cookies the hand-off gave the
   phone, with **exactly** the attributes they were set with (`Secure; SameSite=None; Partitioned`).
   A clear with different attributes writes a different cookie and leaves the live session in place.
7. **Apply the same rule on every upload screen.** When a user adds two or more photos at once
   (gallery pick, drag and drop), compose them into one PDF before uploading as well. PDFs and TIFFs
   (often multi-page faxes) upload as they are. Split into "part 1 of 2" only to stay under the cap,
   keeping every page in order.

## Primary vs fallback

- **Primary — one PDF per capture:** a document-extraction pipeline reads one multi-page document as
  a whole, so the narrative holds together and a table that spans two photos stays in one piece. Its
  maintainers report it's much faster than the same pages as separate images, at the same per-page
  cost, and the record gets one entry instead of N.
- **Fallback — "part 1 of N" PDFs:** only when one PDF would exceed the upload cap; split at page
  boundaries, in order.
- **Not a fallback — one upload per photo.** A case uploaded as 34 separate gallery photos produced
  34 attachments, 34 extraction jobs, and a history summary drawn from only one of them.

## Minimal example

The phone's capture screen (live camera, with the file-input fallback):

```tsx
import { useEffect, useRef, useState } from "react"
import { frameToPage, fileToPage, type PageImage } from "./pages"

export function CaptureScreen({ onDone }: { onDone: (pages: PageImage[]) => void }) {
  const video = useRef<HTMLVideoElement>(null)
  const [pages, setPages] = useState<PageImage[]>([])
  const [cameraOk, setCameraOk] = useState(true)

  useEffect(() => {
    let stream: MediaStream | undefined
    navigator.mediaDevices?.getUserMedia({ video: { facingMode: { ideal: "environment" } } })
      .then((s) => { stream = s; if (video.current) video.current.srcObject = s })
      .catch(() => setCameraOk(false)) // denied, or no camera API: offer the file input instead
    if (!navigator.mediaDevices?.getUserMedia) setCameraOk(false)
    return () => stream?.getTracks().forEach((t) => t.stop())
  }, [])

  const shoot = () => video.current && setPages((p) => [...p, frameToPage(video.current!)])
  const remove = (i: number) => setPages((p) => p.filter((_, j) => j !== i))
  // Fallback photos are camera shots too: same size and quality as a live frame, in the order chosen.
  const addPhotos = async (files: FileList | null) => {
    const added: PageImage[] = []
    for (const file of Array.from(files ?? [])) added.push(await fileToPage(file, 1600, 0.72))
    setPages((p) => [...p, ...added])
  }

  return (
    <div>
      {cameraOk
        ? <><video ref={video} autoPlay playsInline muted /><button onClick={shoot}>Capture page</button></>
        : <input type="file" accept="image/*" capture="environment" multiple onChange={(e) => addPhotos(e.target.files)} />}
      <ol>{pages.map((p, i) => <li key={i}><img src={p.jpegDataUrl} alt={`Page ${i + 1}`} width={80} /><button onClick={() => remove(i)}>Remove</button></li>)}</ol>
      <button disabled={!pages.length} onClick={() => onDone(pages)}>Done</button>
    </div>
  )
}
```

Pages, one PDF under the cap, the upload, and the hand-off calls:

```ts
import { jsPDF } from "jspdf"
import { uploadStepAttachment } from "@/lib/api"

export type PageImage = { jpegDataUrl: string; width: number; height: number }
const UPLOAD_CAP = 25 * 1024 * 1024 // use your own upload limit

/** Paint white first (a transparent PNG turns black in a JPEG), downscale, encode. */
function drawPage(source: CanvasImageSource, w: number, h: number, maxEdge: number, quality: number): PageImage {
  const k = Math.min(1, maxEdge / Math.max(w, h))
  const canvas = Object.assign(document.createElement("canvas"), { width: Math.round(w * k), height: Math.round(h * k) })
  const ctx = canvas.getContext("2d")!
  ctx.fillStyle = "#fff"
  ctx.fillRect(0, 0, canvas.width, canvas.height)
  ctx.drawImage(source, 0, 0, canvas.width, canvas.height) // browsers already apply EXIF orientation
  return { jpegDataUrl: canvas.toDataURL("image/jpeg", quality), width: canvas.width, height: canvas.height }
}

export const frameToPage = (v: HTMLVideoElement) => drawPage(v, v.videoWidth, v.videoHeight, 1600, 0.72)

/** Uploaded images (often screenshots) keep more detail than camera frames by default. */
export async function fileToPage(file: File, maxEdge = 2600, quality = 0.85): Promise<PageImage> {
  const bitmap = await createImageBitmap(file) // rejects where the browser can't decode it (HEIC outside Safari)
  try { return drawPage(bitmap, bitmap.width, bitmap.height, maxEdge, quality) } finally { bitmap.close() }
}

export function composeToPdf(pages: PageImage[], fileName: string): File {
  const doc = new jsPDF({ unit: "pt", format: "a4" })
  const W = doc.internal.pageSize.getWidth(), H = doc.internal.pageSize.getHeight(), M = 24
  pages.forEach((page, i) => {
    if (i > 0) doc.addPage()
    const k = Math.min((W - 2 * M) / page.width, (H - 2 * M) / page.height)
    doc.addImage(page.jpegDataUrl, "JPEG", (W - page.width * k) / 2, (H - page.height * k) / 2, page.width * k, page.height * k)
  })
  return new File([doc.output("blob")], fileName, { type: "application/pdf" })
}

/** One PDF if it fits; otherwise halve at page boundaries until each part fits, keeping page order. */
export function composeUnderCap(pages: PageImage[], baseName: string, cap = UPLOAD_CAP): File[] {
  const parts: File[] = []
  const fit = (group: PageImage[]) => {
    const pdf = composeToPdf(group, `${baseName}.pdf`)
    if (pdf.size <= cap || group.length === 1) return void parts.push(pdf)
    const mid = Math.ceil(group.length / 2)
    fit(group.slice(0, mid))
    fit(group.slice(mid))
  }
  fit(pages)
  return parts.length === 1
    ? parts
    : parts.map((p, i) => new File([p], `${baseName} (part ${i + 1} of ${parts.length}).pdf`, { type: p.type }))
}

/** Upload once per part, under the user's own identity; your server then verifies and records it. */
export async function uploadCapture(stepId: number, pages: PageImage[], recordLabel: string) {
  for (const file of composeUnderCap(pages, `Records ${recordLabel}`)) {
    const res = await uploadStepAttachment(stepId, file) // WorkflowTemplateStep / …HasAttachmentFile
    if (!res.success) throw new Error(res.error)
    const { id } = res.data as { id: number; name: string }
    // Your own route: it confirms `id` is attached to `stepId` before adding it to your manifest.
    await fetch("/api/capture/record", { method: "POST", headers: JSON_HEADERS, body: JSON.stringify({ stepId, fileId: id }) })
  }
}

const JSON_HEADERS = { "Content-Type": "application/json" }

// The link carries "#<nonce>.<sealed session>"; the fragment never reaches a server on page load.
const fromFragment = () => { const [nonce, sealed] = location.hash.slice(1).split("."); return { nonce, sealed } }

/** Page load: valid or not, plus a non-sensitive label. Never burns the ticket. */
export async function peekHandoff(recordId: number): Promise<{ valid: boolean; label?: string }> {
  const res = await fetch(`/api/handoff/${recordId}/peek`, { method: "POST", headers: JSON_HEADERS, body: JSON.stringify(fromFragment()) })
  return res.ok ? res.json() : { valid: false }
}

/** The explicit "Start" tap: the only call that redeems (and burns) the ticket. */
export async function startCapture(recordId: number) {
  const res = await fetch(`/api/handoff/${recordId}/redeem`, { method: "POST", headers: JSON_HEADERS, body: JSON.stringify(fromFragment()) })
  if (!res.ok) throw new Error("This link has expired or was replaced by a newer one. Open the latest link.")
}
```

## Gotchas

- **Link previews burn GET links.** Messaging apps fetch links with GET to build a preview, so a
  link that redeems on GET arrives already spent. Peek on GET; burn only on an explicit POST.
- **The newest link wins.** Showing the QR again or re-sending the text mints a new ticket and
  invalidates the old link. Say so in the UI.
- **Camera access needs HTTPS** (and a user gesture on some phones). Test the file-input fallback
  path too.
- **Size before upload.** Downscale before composing, and check the composed size against your
  upload cap (e.g. 25 MB).
- **Uploaded screenshots need more detail than camera frames.** Keep up to about 2600 px at quality
  about 0.85; dense tables become hard to read at 1600 px.
- **Transparent PNGs turn black** when drawn into a JPEG. Paint a white background first.
- **HEIC decodes in the browser only in Safari.** Elsewhere, upload a HEIC file on its own rather
  than failing the whole batch.
- **Keep pages in the order the user captured or selected them.**
- **Don't rotate twice.** Current browsers already apply EXIF orientation when drawing an image to a
  canvas.
- **Text the link only to a verified mobile** ([add-a-phone-for-mfa.md](add-a-phone-for-mfa.md)).

## Related

- [qr-device-session-handoff.md](qr-device-session-handoff.md) — minting, sealing and redeeming the
  one-time link.
- [client-side-pdf-authoring.md](client-side-pdf-authoring.md) — composing pages into one PDF.
- [attachments.md](attachments.md) — the step attachment relation the PDF lands on.
- [native-email-and-sms.md](native-email-and-sms.md) — texting the link.
- [poll-and-diff-live-sync.md](poll-and-diff-live-sync.md) — the desktop noticing the new file.
- [external-job-pipeline.md](external-job-pipeline.md) — reading the PDF once, on the desktop.
- [iframe-embedding-cookies.md](iframe-embedding-cookies.md) — why the session cookies carry
  `Secure; SameSite=None; Partitioned`.
- [add-a-phone-for-mfa.md](add-a-phone-for-mfa.md) — the verified mobile the link can be texted to.
