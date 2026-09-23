# Ask the platform to generate a document instead of compositing one yourself

**Use when:** you need a lab requisition, a test-result report, a branded (letterhead-merged)
requisition, or every file attached to an order — for these specific document kinds, ask 1health
for the finished PDF instead of compositing one yourself.
**Routes:** `GET /api/v2/pdf/order/{id}/requisition` → [agents.md](https://agents.1health.io/public/prod/api/v2/pdf/order/_id_/requisition/agents.md) · `GET /api/v2/pdf/order/{id}/test-result` → [agents.md](https://agents.1health.io/public/prod/api/v2/pdf/order/_id_/test-result/agents.md) · `POST /api/v2/pdf/order/{id}/generate-branded-requisition` → [agents.md](https://agents.1health.io/public/prod/api/v2/pdf/order/_id_/generate-branded-requisition/agents.md) · `GET /api/v2/health/order/{id}/file/all/zip` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/order/_id_/file/all/zip/agents.md)
**Reference code:** none public — see the Minimal example
**Seen in:** 1health platform usage

## Pattern

1. For a well-known document kind the platform already knows how to generate — a requisition, a
   test-result report, a branded requisition — ask for it directly and stream back the response;
   there's no request body for the plain requisition/result variants.
2. For the branded variant, upload your own letterhead/branding PDF as multipart under the
   documented file field; the platform merges it with the order's requisition. Check the response's
   content type before assuming it's a raw PDF stream versus a small JSON record describing the
   generated file — confirm which shape your tenant returns against demo.
3. For "give me everything attached to this order," call the all-files zip endpoint instead of
   looping per-file downloads — it bundles every journey-step attachment plus the generated
   requisition and result PDFs in one archive.
4. Reserve your own server-side compositing ([server-side-pdf-rendering.md](server-side-pdf-rendering.md))
   for document kinds the platform doesn't already generate — a stamped agreement, anything whose
   content is specific to your own app's data.

## Primary vs fallback

- **Primary — ask the platform (`/api/v2/pdf/order/{id}/...`):** always try this first for a
  requisition, result report, branded requisition, or the all-files zip — 1health already
  generates these, nothing (or a branding template) in, a document out.
- **Fallback — composite it yourself** ([server-side-pdf-rendering.md](server-side-pdf-rendering.md)):
  for any document kind the platform doesn't generate, or whose content depends on facts only your
  own app tracks.

## Minimal example

```ts
import { authFetch, getOneHealthBaseUrl } from "@/lib/auth-client"

// Plain requisition/result — GET and stream the blob, no request body.
async function fetchOrderRequisition(orderId: number): Promise<Blob> {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/v2/pdf/order/${orderId}/requisition`)
  if (!response.ok) throw new Error(`Fetch failed: ${response.status}`)
  return response.blob()
}

// Branded variant — upload your own letterhead template as multipart.
async function generateBrandedRequisition(orderId: number, brandingTemplate: File): Promise<Blob> {
  const baseUrl = getOneHealthBaseUrl()
  const form = new FormData()
  form.append("pdfFile1", brandingTemplate)
  const response = await authFetch(
    `${baseUrl}/api/v2/pdf/order/${orderId}/generate-branded-requisition`,
    { method: "POST", body: form },
  )
  if (!response.ok) throw new Error(`Generate failed: ${response.status}`)
  return response.blob()
}

// Everything attached to the order, in one archive.
async function fetchAllOrderFiles(orderId: number): Promise<Blob> {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/v2/health/order/${orderId}/file/all/zip`)
  if (!response.ok) throw new Error(`Fetch failed: ${response.status}`)
  return response.blob()
}
```

## Gotchas

- **The plain requisition/result/zip responses are blobs** — don't try to parse them as JSON; set
  the appropriate response handling and `Content-Type` client-side.
- **The branded-requisition upload uses a fixed form-field name** — match it exactly or the upload
  is silently ignored, and verify whether your tenant streams the merged PDF directly or returns a
  file record you then need to download.
- **The all-files zip already includes the generated requisition and result PDFs** alongside step
  attachments — don't also fetch those individually and end up with duplicates.
- **This only covers document kinds the platform already knows how to generate** — anything else
  (a stamped agreement, an app-specific summary) still needs your own compositing step.

## Related

- [server-side-pdf-rendering.md](server-side-pdf-rendering.md) — the fallback compositing approach,
  and its own gotchas about server-only PDF libraries.
- [orders-and-master-orders.md](orders-and-master-orders.md) — the order these documents are
  generated for.
- [attachments.md](attachments.md) — general file/blob-handling gotchas that also apply here.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
