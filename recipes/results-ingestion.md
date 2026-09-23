# Submit a test result, structured or as a file

**Use when:** an order's test is complete and you need to record its result — as discrete data or
as a report/image file — or you're defining what counts as a valid result for a test in the first
place, or backfilling a historical result that has no live order.
**Routes:** `POST /api/v2/health/order/{orderId}/test-result` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/order/_orderId_/test-result/agents.md) · `POST /api/v2/health/order/{orderId}/test-result/file` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/order/_orderId_/test-result/file/agents.md) · `GET/POST/PUT/DELETE /api/v2/health/compendium/{testOfferedId}/result` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/compendium/_testOfferedId_/result/agents.md) · `POST /api/v2/health/compendium/{testOfferedId}/result-definition` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/compendium/_testOfferedId_/result-definition/agents.md) · `POST /api/v2/health/encounter/old-result/data-file` (+ sibling `dna-traits`/`qualitative`/`quantitative` variants) → [agents.md](https://agents.1health.io/public/prod/api/v2/health/encounter/old-result/data-file/agents.md)
**Reference code:** none public — see the Minimal example
**Seen in:** 1health platform usage

## Pattern

1. **Decide by shape, not preference.** A discrete value (a number, a qualitative call) is a
   **structured** result; a report/image/PDF output is a **file** result. Both are permanent,
   first-class paths — the result's own shape decides which endpoint you call, every time.
2. **Define what a valid result looks like on the test catalog entry, not with generic custom
   fields.** A per-test result *definition* is its own typed sub-resource under the test-offered's
   id: a name, coded (e.g. LOINC) identifiers, a closed data type (`"Quantitative"` /
   `"Qualitative"` / `"Data File"` / `"PDF or Image"`), a unit drawn from a controlled list, and —
   only for `"Quantitative"` — numeric lower/upper bounds. Reach for a bespoke typed sub-resource
   like this instead of generic admin-defined custom fields whenever a field family has cross-field
   rules tied to a type selector.
3. **Browse result definitions through their own paginated call**, not the CRUD-by-id route — and
   read whatever page-size cap it enforces server-side rather than assuming an arbitrarily large
   page works.
4. **Expect a submitted result to be looser than its own definition.** The reference range that
   ships with one result is a free-form map, not the two typed bounds the definition declares —
   different result shapes need different reference-value structures.
5. **Use the legacy old-result family only to backfill history with no live order.** It's organized
   by result *shape* (`data-file` / `dna-traits` / `qualitative` / `quantitative`), which doesn't
   line up one-to-one with the live-order result endpoints — treat it as a separate, migration-only
   surface, and send the structured payload as a JSON string in a `dto` form field alongside the
   file(s), not as a plain JSON body.

## Primary vs fallback

- **Primary — structured (`POST .../test-result`):** the value is discrete data — a number or a
  qualitative call.
- **Fallback — file (`POST .../test-result/file`, multipart, `resultName` + `attachment`
  required):** the output is a report/image/PDF. Switch the moment the result itself isn't a
  scalar value.

## Minimal example

```ts
import { authFetch, getOneHealthBaseUrl } from "@/lib/auth-client"

// PRIMARY — structured result. The nested per-result fields follow whatever that test's own
// result definition declares (below); confirm them against a real definition before hardcoding.
async function submitStructuredResult(orderId: number, results: Array<Record<string, unknown>>) {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/v2/health/order/${orderId}/test-result`, {
    method: "POST",
    body: JSON.stringify({ results, accessionDate: new Date().toISOString() }),
  })
  if (!response.ok) throw new Error(`Submit failed: ${response.status}`)
}

// FALLBACK — file result (a report/image/PDF). `resultName` is required both as a form field
// and as a query parameter.
async function submitFileResult(orderId: number, resultName: string, file: File) {
  const baseUrl = getOneHealthBaseUrl()
  const form = new FormData()
  form.append("resultName", resultName)
  form.append("attachment", file)
  const response = await authFetch(
    `${baseUrl}/api/v2/health/order/${orderId}/test-result/file?resultName=${encodeURIComponent(resultName)}`,
    { method: "POST", body: form },
  )
  if (!response.ok) throw new Error(`Submit failed: ${response.status}`)
}

// Defining what a valid result IS, on the test catalog entry — a bespoke typed sub-resource.
interface ResultSpec {
  name: string
  loinc?: Array<{ code: string; description?: string }>
  resultType: "Quantitative" | "Qualitative" | "Data File" | "PDF or Image"
  uom?: string                                // only meaningful for Quantitative
  lowerRange?: number; upperRange?: number    // only sent when resultType === "Quantitative"
}

async function defineResult(testOfferedId: number, def: ResultSpec) {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/v2/health/compendium/${testOfferedId}/result`, {
    method: "POST",
    body: JSON.stringify(def),
  })
  if (!response.ok) throw new Error(`Define failed: ${response.status}`)
}
```

## Gotchas

- **A submitted result's own reference range is a free-form map**, not the definition's two typed
  bounds — don't assume the same shape round-trips both ways.
- **`resultName` is required on the file path both as a form field and as a query parameter** —
  sending it in only one place fails.
- **The result-definition list enforces a server-side page-size cap** — a documented past failure
  mode; read the cap rather than requesting an arbitrarily large page.
- **The legacy old-result family sends its payload as a JSON-stringified `dto` form field plus a
  `files` part** — a plain JSON body doesn't work there, even though the live-order structured
  endpoint takes plain JSON.
- **The old-result shape families don't map one-to-one onto the live-order endpoints** — pick the
  variant (`data-file`/`dna-traits`/`qualitative`/`quantitative`) by the historical data's own
  shape, and only reach for this family when there's no live order to attach to.

## Related

- [test-catalog-modeling.md](test-catalog-modeling.md) — the test-offered a result definition
  hangs off.
- [external-record-to-medical-record.md](external-record-to-medical-record.md) — the generic
  clinical-record attach, for data that isn't a test result.
- [typed-custom-field-definitions.md](typed-custom-field-definitions.md) — contrast: the generic
  admin-defined-field mechanism this pattern deliberately avoids.
- [attachments.md](attachments.md) — general multipart-upload gotchas that also apply to file
  results.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
