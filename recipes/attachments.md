# Attachments

**Use when:** you need to attach a file to a record — a free-standing upload distinct from a step's own `fileUpload` dynamic field — and later list, download, or delete it.
**Routes:** `POST /api/v2/health/type/_EntityType_/_id_/relation/_RelationName_/file/upload` — generic typed-entity relation upload; confirm the exact shape via the [manifest](https://agents.1health.io/public/prod/api/manifest.md) (two dynamic segments beyond the id, so don't trust a guessed `agents.md` link) · `GET /api/v2/journey/_journeyId_/documents` → [route docs](https://agents.1health.io/public/prod/api/manifest.md) · `GET /api/v2/file/_fileId_/download` → [route docs](https://agents.1health.io/public/prod/api/manifest.md) · `DELETE /api/v2/file/_fileId_?hardDelete=true` → [route docs](https://agents.1health.io/public/prod/api/manifest.md)
**Reference code:** [`lib/api/journey-attachments.ts`](https://github.com/Tachin-ai-Corporation/v0-trc-care-coordinator/blob/main/lib/api/journey-attachments.ts) · [`lib/api/files.ts`](https://github.com/Tachin-ai-Corporation/v0-trc-care-coordinator/blob/main/lib/api/files.ts)
**Seen in:** trc-care-coordinator (also a template-baseline capability; seen too in secure-share)

## Pattern

1. Know which of two file mechanisms you need: a step's own `fileUpload` dynamic field (submitted through the normal step-submit call — see the workflows recipes) vs. a **free-standing** attachment not tied to any dynamic field. This recipe is the second one.
2. Upload via the generic typed-entity relation route, keyed by the owning instance's **type**, **id**, and the **relation name** that links it to attachments (e.g. `WorkflowTemplateStepHasAttachmentFile`). The route is generic — the same shape works for any entity type that exposes such a relation.
3. Send the binary as `multipart/form-data` under a `file` field; the filename travels as a **query parameter**, URL-encoded, not as multipart metadata.
4. Don't list attachments with `/query` — read them nested under their owning record's own detail read (e.g. a journey's steps each carry their own `attachments` array).
5. Download by the file's own id, then rebuild a `Blob` client-side; delete removes the `File` instance itself (`hardDelete=true`) — there's no separate "detach without deleting."

## Minimal example

```ts
import { authFetch, getOneHealthBaseUrl } from "@/lib/auth-client"

/**
 * Upload a free-standing attachment via the generic relation-upload route.
 * e.g. entityType="WorkflowTemplateStep", relationName="WorkflowTemplateStepHasAttachmentFile"
 */
async function uploadAttachment(entityType: string, entityId: number, relationName: string, file: File) {
  const baseUrl = getOneHealthBaseUrl()
  const url =
    `${baseUrl}/api/v2/health/type/${entityType}/${entityId}/relation/${relationName}/file/upload` +
    `?fileName=${encodeURIComponent(file.name)}&isPublic=false`

  const formData = new FormData()
  formData.append("file", file, file.name)

  const response = await authFetch(url, { method: "POST", body: formData })
  if (!response.ok) throw new Error(`Upload failed: ${response.status}`)
  return response.json() // => { id, name, publicUrl, ... }
}

// Attachments come back NESTED under the owning record's own read — not a /query.
async function fetchJourneyDocuments(journeyId: number) {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/v2/journey/${journeyId}/documents`)
  if (!response.ok) throw new Error(`Fetch failed: ${response.status}`)
  return response.json() // => { workflowSteps: [{ attachments: [...] }] }
}

// Delete removes the File instance itself — there is no soft delete.
async function deleteFile(fileId: number) {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/v2/file/${fileId}?hardDelete=true`, { method: "DELETE" })
  if (!response.ok) throw new Error(`Delete failed: ${response.status}`)
}
```

## Gotchas

- Two distinct file mechanisms exist — a step's `fileUpload` dynamic field vs. this generic relation upload for a free-standing attachment. Don't conflate them; they're submitted completely differently.
- The upload URL takes the filename as a **query parameter**, URL-encoded — the multipart body carries only the bytes.
- `DELETE .../file/{id}` needs `?hardDelete=true`; without it the file may only be soft-flagged and keeps showing up in reads.
- The platform's stored MIME type isn't always what you want for inline preview (e.g. a generic `application/octet-stream`) — re-wrap the downloaded `Blob` with an explicit `type` client-side when you need in-browser preview instead of a forced download.
- Attachments are read nested under their owning record, not via a standalone `/query` on a "File"/"Attachment" type.
- Revoke any `Blob` URL you create (`URL.revokeObjectURL`) once the viewer is done, or you leak memory over a long session.

## Related

- [comments.md](comments.md) — the other journey-collaboration primitive.
- [query-the-data-graph.md](query-the-data-graph.md) — the general read path; contrast with the nested-read approach here.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md).
