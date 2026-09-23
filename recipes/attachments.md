# Attachments

**Use when:** you need to attach a file to a record — a free-standing upload distinct from a step's own `fileUpload` dynamic field — and later list, download, or delete it.
**Routes:** `POST /api/v2/health/type/_EntityType_/_id_/relation/_RelationName_/file/upload` — generic typed-entity relation upload; confirm the exact shape via the [manifest](https://agents.1health.io/public/prod/api/manifest.md) (two dynamic segments beyond the id, so don't trust a guessed `agents.md` link) · `GET /api/v2/journey/_journeyId_/documents` → [route docs](https://agents.1health.io/public/prod/api/manifest.md) · `GET /api/v2/file/all/_typeKey_/_instanceId_` (repeatable `relKeys` param) → [agents.md](https://agents.1health.io/public/prod/api/v2/file/all/agents.md) · `GET /api/v2/file/_fileId_/download` → [route docs](https://agents.1health.io/public/prod/api/manifest.md) · `POST /api/v2/file/_fileId_/version` → [agents.md](https://agents.1health.io/public/prod/api/v2/file/_fileInstanceId_/version/agents.md) · `DELETE /api/v2/file/_fileId_` → [route docs](https://agents.1health.io/public/prod/api/manifest.md)
**Reference code:** [`lib/api/journey-attachments.ts`](https://github.com/Tachin-ai-Corporation/v0-trc-care-coordinator/blob/main/lib/api/journey-attachments.ts) · [`lib/api/files.ts`](https://github.com/Tachin-ai-Corporation/v0-trc-care-coordinator/blob/main/lib/api/files.ts)
**Seen in:** trc-care-coordinator (also a template-baseline capability; seen too in secure-share) · 1health platform usage (multi-relation listing, versions, WAF workaround)

## Pattern

1. Know which of two file mechanisms you need: a step's own `fileUpload` dynamic field (submitted through the normal step-submit call — see the workflows recipes) vs. a **free-standing** attachment not tied to any dynamic field. This recipe is the second one.
2. Upload via the generic typed-entity relation route, keyed by the owning instance's **type**, **id**, and the **relation name** that links it to attachments (e.g. `WorkflowTemplateStepHasAttachmentFile`). The route is generic — the same shape works for any entity type that exposes such a relation.
3. Send the binary as `multipart/form-data` under a `file` field; the filename travels as a **query parameter**, URL-encoded, not as multipart metadata.
4. Don't list attachments with `/query`. Two listing options exist instead: read them nested under
   their owning record's own detail read (e.g. a journey's steps each carry their own `attachments`
   array) — the default — or, when you need every file across **one or several** relations on an
   instance in a single flat call, use the dedicated list-by-instance endpoint with a repeatable
   `relKeys` param.
5. To version a file, upload the new binary via `POST /api/v2/file/{fileId}/version` with a "make
   this the current version" flag and an optional version label. A version is just another id in the
   same id-space as the file itself — the download route transparently accepts either one.
6. Download by the file's own id (or a version id — see above), then rebuild a `Blob` client-side.
   Deleting has two modes — see Primary vs fallback below.
7. When a single write needs to carry both structured data **and** one or more files together,
   atomically, use the JSON-payload-plus-files multipart convention instead of this recipe's plain
   `file` field: stringify the structured part into its own form field, then append each file under
   its own field name in the same request.

## Primary vs fallback

- **Primary — hard delete (`?hardDelete=true`):** purges the file from storage. Use it when
  "delete" should really mean gone — e.g. a user retracting their own mistaken upload.
- **Fallback — soft delete (omit the flag):** the default when `hardDelete` isn't passed at all —
  only flags the record and leaves it recoverable. Reach for this when deletion should be undoable,
  or when you want removed files to still show up in an audit trail.

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

// Alternative listing: every file across one or several relations, in one flat call.
async function listAttachmentsByRelations(entityType: string, entityId: number, relationNames: string[]) {
  const baseUrl = getOneHealthBaseUrl()
  const params = new URLSearchParams()
  relationNames.forEach((name) => params.append("relKeys", name))
  const response = await authFetch(`${baseUrl}/api/v2/file/all/${entityType}/${entityId}?${params}`)
  if (!response.ok) throw new Error(`List failed: ${response.status}`)
  return response.json() // => flat array of file instances
}

// PRIMARY — hard delete purges the File instance from storage.
// FALLBACK — omit `hardDelete` to soft-delete instead (recoverable; see Primary vs fallback).
async function deleteFile(fileId: number, hardDelete = true) {
  const baseUrl = getOneHealthBaseUrl()
  const params = hardDelete ? "?hardDelete=true" : ""
  const response = await authFetch(`${baseUrl}/api/v2/file/${fileId}${params}`, { method: "DELETE" })
  if (!response.ok) throw new Error(`Delete failed: ${response.status}`)
}
```

## Gotchas

- Two distinct file mechanisms exist — a step's `fileUpload` dynamic field vs. this generic relation upload for a free-standing attachment. Don't conflate them; they're submitted completely differently.
- The upload URL takes the filename as a **query parameter**, URL-encoded — the multipart body carries only the bytes.
- `DELETE .../file/{id}` only hard-purges the file with `?hardDelete=true` — omit it **deliberately**
  for the soft-delete fallback (see Primary vs fallback above), not by accident.
- The platform's stored MIME type isn't always what you want for inline preview (e.g. a generic `application/octet-stream`) — re-wrap the downloaded `Blob` with an explicit `type` client-side when you need in-browser preview instead of a forced download.
- Attachments are read nested under their owning record by default, not via a standalone `/query` on
  a "File"/"Attachment" type — reach for the relation-scoped list endpoint above only when you need
  files from more than one relation in a single call.
- Revoke any `Blob` URL you create (`URL.revokeObjectURL`) once the viewer is done, or you leak memory over a long session.
- A raw, unauthenticated `fetch` you sometimes see near an upload flow is usually for reading back a
  **static asset URL** a record already returned (e.g. a generated report/template link) — not a
  presigned upload target. Sending bytes to the platform always goes through the authenticated
  multipart route above; a raw fetch is only for retrieving a blob from a URL that isn't itself a
  `/api/...` route.
- Some structurally valid binary uploads (images, PDFs) can be rejected at a network-edge firewall in
  front of the API for reasons uncorrelated with file validity — the compressed bytes coincidentally
  contain a signature the firewall's body inspection flags. Prefer an infrastructure rule exclusion
  for the specific upload route if you control it; the fallback is sending the binary base64-encoded
  inside a JSON string field instead of raw multipart bytes — but only if the receiving endpoint
  actually decodes that field server-side, or the write silently becomes a no-op.
- A call expecting this kind of binary/blob response can still come back as a JSON error body — the
  client hands you a `Blob` either way. Sniff its MIME type and, if it says JSON, read it as text and
  parse it before treating it as the real error; see
  [request-funnel-and-error-tiers.md](request-funnel-and-error-tiers.md).

## Related

- [comments.md](comments.md) — the other journey-collaboration primitive.
- [query-the-data-graph.md](query-the-data-graph.md) — the general read path; contrast with the nested-read approach here.
- [request-funnel-and-error-tiers.md](request-funnel-and-error-tiers.md) — the shared error handling that should own the blob/JSON-error check.
- [bulk-import.md](bulk-import.md) — another route that uses the JSON-payload-plus-files multipart convention.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md).
