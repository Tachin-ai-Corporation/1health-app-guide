# Patient documents (attachments)

**Use when:** you need to store and retrieve binary documents (lab results, imaging, clinical
notes) attached to a patient record, with soft-delete and time-limited download links.
**Routes:** `GET/POST/DELETE /v3/patient/{id}/attach[/{documentId}]` → a child route of [route docs](https://agents.1health.io/public/prod/api/manifest.md); confirm the exact contract there or via the [manifest](https://agents.1health.io/public/prod/api/manifest.md)
**Reference code:** [`lib/api/documents.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/api/documents.ts)
**Seen in:** patient-vault

## Pattern

1. **Encode the file yourself.** Unlike the platform's generic file-relation upload (multipart),
   this attachment endpoint takes JSON: base64-encode the file contents client-side and send them
   as a `data` string field alongside `name`/`documentType`/`contentType`.
2. **List for browsing, fetch-by-id for downloading.** The list endpoint returns lightweight
   summary rows (no download link). Before every download, call the single-document GET to obtain
   a **freshly issued** `downloadUrl` — never reuse one from an earlier fetch or from the list.
3. **Treat delete as a status change, not a removal.** Deleting deactivates the record; the file is
   retained and reappears if the caller queries with a status filter that includes deactivated
   documents. Model your UI's "delete" as "hide from the active view," and your status filter as
   three states (active/all/deleted), not a boolean.
4. **Normalize the id field defensively** when mapping the raw response — different
   endpoints/versions spell it `documentId`, `id`, `documentID`, or `attachmentId`.

## Minimal example

```ts
import { callApi } from "@/lib/api"

interface DocumentDTO {
  documentId: string; name: string; documentType?: string; contentType?: string
  downloadUrl?: string | null; deleted?: boolean
}

function normalizeDoc(raw: any): DocumentDTO {
  const id = raw.documentId ?? raw.id ?? raw.documentID ?? raw.attachmentId
  return { ...raw, documentId: id == null ? "" : String(id) }
}

export async function attachDocument(
  personId: string,
  file: { name: string; contentType: string; base64: string },
  documentType: string,
) {
  const res = await callApi<unknown>("document/attach", `/v3/patient/${personId}/attach`, {
    method: "POST",
    body: JSON.stringify({ documentType, contentType: file.contentType, name: file.name, data: file.base64 }),
  })
  return normalizeDoc(res.data)
}

export async function listDocuments(personId: string, status: "active" | "all" | "deleted" = "active") {
  const qs = status === "all" ? "?active=all" : status === "deleted" ? "?active=false" : ""
  const res = await callApi<unknown>("document/list", `/v3/patient/${personId}/attach${qs}`)
  const rows = Array.isArray(res.data) ? res.data : (res.data as any)?.documents ?? []
  return rows.map(normalizeDoc)
}

// Always call this immediately before download — the URL expires ~15 min after issue.
export async function getFreshDownloadUrl(personId: string, documentId: string) {
  const res = await callApi<unknown>("document/get", `/v3/patient/${personId}/attach/${documentId}`)
  return normalizeDoc(res.data).downloadUrl ?? null
}

export async function deleteDocument(personId: string, documentId: string) {
  return callApi("document/delete", `/v3/patient/${personId}/attach/${documentId}`, { method: "DELETE" })
}
```

## Gotchas

- **`downloadUrl` expires roughly 15 minutes after issue** — fetch it fresh immediately before each
  download; don't cache it alongside the document metadata.
- **This endpoint wants base64 JSON, not multipart** — don't reuse your generic file-upload helper
  here.
- **Delete is a soft deactivate** — the file and its metadata survive and reappear under a status
  filter; don't treat a "deleted" document as gone for retention/compliance purposes.
- **Normalize the id field on every response** — its spelling isn't guaranteed consistent across
  list vs. detail payloads.

## Related

- [patient-crud.md](patient-crud.md)
- [attachments.md](attachments.md) — the platform's general-purpose file-relation upload, for
  non-patient entities.
- [external-record-to-medical-record.md](external-record-to-medical-record.md) — attaching a
  document's *extracted data* as a clinical record, as opposed to storing the raw file here.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
