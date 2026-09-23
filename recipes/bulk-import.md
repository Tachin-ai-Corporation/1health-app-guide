# Bulk-import records from a file

**Use when:** a caller needs to upload a spreadsheet/file to create or update many records in one
shot (loading a patient list, a catalog, any admin-bulk-loaded data) instead of one create call per row.
**Routes:** discover types via `POST /api/graphql` → [agents.md](https://agents.1health.io/public/prod/api/graphql/agents.md) · `POST /api/v2/data/query-key/_queryKey_/custom-import/start` → [agents.md](https://agents.1health.io/public/prod/api/v2/data/query-key/_queryKey_/custom-import/start/agents.md) · `POST /api/v2/data/query-key/_queryKey_/import/start` → [agents.md](https://agents.1health.io/public/prod/api/v2/data/query-key/_queryKey_/import/start/agents.md) · `GET /api/v2/file/template/_key_/download` → [agents.md](https://agents.1health.io/public/prod/api/v2/file/template/_key_/download/agents.md) · `POST /api/v3/health/grid/data-import-log` → [agents.md](https://agents.1health.io/public/prod/api/v3/health/grid/data-import-log/agents.md)
**Reference code:** none public — see the Minimal example
**Seen in:** 1health platform usage

## Pattern

1. Discover which import types the caller's org may run **at runtime** — query the platform's
   import/export template-definition catalogue (a GraphQL business type) filtered by the caller's
   own organization type(s), rather than hardcoding a fixed list of import keys.
2. For each import type the catalogue reports, offer a template download first
   (`GET /api/v2/file/template/{key}/download`) so the caller knows the expected columns before
   filling anything in.
3. Start the job with the **custom** import shape (see Primary vs fallback): one multipart request
   carrying the file plus a JSON side-channel of extra options. It returns immediately with a log
   id — the import itself runs in the background.
4. Poll the import log grid (`POST /api/v3/health/grid/data-import-log`), filtered to that log id,
   until the row's `status` is terminal — `SUCCESS`, `PARTIAL_SUCCESS`, or `FAILURE` (confirmed
   against the demo environment). A 200 from the start call only means "the job was accepted," never
   "it succeeded." Each row also carries `numberOfSuccessfulRecords`, `numberOfFailedRecords`, and
   `importExportTemplateDefinitionName` (which import type ran).
5. When a row shows failures, its per-record errors come back as a separate file referenced by the
   row's `errorFileId` / `errorFileName` — offer it as a download (see [attachments.md](attachments.md))
   rather than trying to parse error detail out of the log row itself.
6. If you're rendering a dashboard of every currently-running import instead of polling one job you
   started, remember the log is paginated: OR a "still running" check across every page you read on
   each refresh, and reset that check at the start of every fresh poll — a stale later page can
   otherwise flicker an in-progress banner forever.

## Primary vs fallback

- **Primary — the "custom" import (`custom-import/start`):** file plus a JSON options part in one
  multipart call. Every import type the catalogue currently reports supports this shape, and it's
  the only way to carry extra options — e.g. a tag mutation on the imported rows (see
  [bulk-tagging.md](bulk-tagging.md)) — alongside the data in the same request.
- **Fallback — the plain import (`import/start`):** file plus a couple of fixed format fields
  (`fileFormat`, `multiValueFormat`), no options side-channel. Switch to this only for an import
  type the catalogue reports as not supporting the custom shape.

## Minimal example

```ts
import { authFetch, getOneHealthBaseUrl } from "@/lib/auth-client"

interface ImportTypeDefinition {
  queryKey: string
  label: string
  supportsCustomImport: boolean
}

// Discover which import types this org may run — never hardcode the list.
async function fetchAvailableImportTypes(orgTypes: string[]): Promise<ImportTypeDefinition[]> {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/graphql`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      query: `query ($filter: ImportExportTemplateDefinitionFilterInput) {
        ImportExportTemplateDefinition(filter: $filter) { records { queryKey, label, supportsCustomImport } }
      }`,
      variables: { filter: { supportedByOrganizationTypes: { in: orgTypes } } },
    }),
  })
  const body = await response.json()
  return body?.data?.ImportExportTemplateDefinition?.records ?? []
}

interface TagOptions { tagAction?: "ADD" | "REMOVE" | "REPLACE"; addTags?: number[]; removeTags?: number[] }

// PRIMARY — the "custom" import: file + a JSON options part, one multipart call.
async function startCustomImport(queryKey: string, file: File, tagOptions?: TagOptions): Promise<number> {
  const baseUrl = getOneHealthBaseUrl()
  const form = new FormData()
  form.append("rawData[0].file", file)
  form.append("rawData[0].data", JSON.stringify(tagOptions ?? {}))
  const response = await authFetch(`${baseUrl}/api/v2/data/query-key/${queryKey}/custom-import/start`, {
    method: "POST",
    body: form,
  })
  if (!response.ok) throw new Error(`Import failed to start: ${response.status}`)
  return (await response.json()).sysDataImportLogId
}

// FALLBACK — only for an import type the catalogue reports as NOT custom-capable.
async function startLegacyImport(queryKey: string, file: File): Promise<number> {
  const baseUrl = getOneHealthBaseUrl()
  const form = new FormData()
  form.append("file", file)
  const params = new URLSearchParams({ fileFormat: "TSV", multiValueFormat: "PIPE" })
  const response = await authFetch(`${baseUrl}/api/v2/data/query-key/${queryKey}/import/start?${params}`, {
    method: "POST",
    body: form,
  })
  if (!response.ok) throw new Error(`Import failed to start: ${response.status}`)
  return (await response.json()).importId
}

// Poll the log for THIS job's own row until its outcome is terminal.
const TERMINAL = new Set(["SUCCESS", "PARTIAL_SUCCESS", "FAILURE"])

async function pollImportOutcome(logId: number, { intervalMs = 5000, maxAttempts = 60 } = {}) {
  const baseUrl = getOneHealthBaseUrl()
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const response = await authFetch(`${baseUrl}/api/v3/health/grid/data-import-log?page=0&size=1`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ filterBy: [{ key: "id", operator: "equals", value: logId }] }),
    })
    const { data } = await response.json()
    const row = data?.[0]
    // Terminal statuses confirmed on demo; the row also has numberOfSuccessfulRecords,
    // numberOfFailedRecords, and errorFileId (the per-record error report) when anything failed.
    if (row && TERMINAL.has(row.status)) return row
    await new Promise((resolve) => setTimeout(resolve, intervalMs))
  }
  throw new Error("Import polling timed out")
}
```

## Gotchas

- Discover import types via the catalogue query — the set of import keys an org may run depends on
  org type and isn't fixed; hardcoding a list drifts as the platform adds or retires import types.
- The "custom" shape's file and options parts are indexed multipart fields (`rawData[0].file`,
  `rawData[0].data`) — the options part is a plain JSON string field, not a nested multipart object.
- Both start calls return immediately; a 200 means the job was accepted, not that it finished —
  always resolve the real outcome from the import log, never from the start call's response alone.
- No cancel action is exposed for an in-flight import — once started, the caller can only wait it
  out or ignore the result.
- Fetch the template fresh per import type (the download key matches that type's own `queryKey`)
  rather than caching one shared "the" template across types.

## Related

- [bulk-tagging.md](bulk-tagging.md) — the add/remove/replace tag semantics carried in the custom
  import's options part.
- [grid-list-views.md](grid-list-views.md) — the same grid engine backs the import log you poll here.
- [../api/README.md](../api/README.md)
