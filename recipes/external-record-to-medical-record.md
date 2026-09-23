# External extractor → 1health medical record

**Use when:** an external system (a document-extraction pipeline, a health-information exchange)
has produced structured clinical data for a patient, and you want it to live as a first-class,
queryable 1health clinical record rather than trapped in your own customData or a third-party
store. If what you're attaching is specifically a lab/test result rather than general clinical
documentation, a more specific ingestion family exists — see
[results-ingestion.md](results-ingestion.md) — and is usually the better fit.
**Routes:** `POST /v2/person/{id}/medical-record` → [route docs](https://agents.1health.io/public/prod/api/manifest.md) · read-back via `POST /api/v2/query` → [agents.md](https://agents.1health.io/public/prod/api/v2/query/agents.md)
**Reference code:** [`lib/api/medical-record.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/api/medical-record.ts) · [`lib/api/cqd.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/api/cqd.ts)
**Seen in:** pcp-tcm, expertdx

## Pattern

1. **Normalize the external vendor's shape onto the platform's before attaching.** A clinical-record
   endpoint may accept a vendor-shaped data list **verbatim, extra keys and all** — but a small
   number of fields validate against 1health's own closed vocabularies (e.g. an encounter
   classification). Coerce just those fields to the accepted set (map recognizable values through;
   fall back to a safe default like "Unknown" rather than fabricating a guess) and forward
   everything else untouched.
2. **Attach by reference, not by re-upload, when the binary is already on the platform.** If the
   source file was already uploaded elsewhere (e.g. as a workflow-step attachment), pass its file
   id to the medical-record call instead of re-uploading — one binary, multiple references.
3. **Expect — and handle — a whole-attach rejection naming exactly what it didn't like.** A single
   unrecognized "evidence definition" or an unrecognized record-type name 400s the **entire**
   record, not just that entry. Parse the rejected name(s) out of the error, strip only those, and
   retry, so the rest of the patient's clinical data still reaches their chart (see
   [closed-vocabulary-writes.md](closed-vocabulary-writes.md) for the general form of this idiom).
   Treat any declared record "type" as optional dressing — retry untyped rather than losing the
   record.
4. **Keep only an id, not the payload, in your own state.** Once attached, store the resulting
   record id (e.g., in the owning journey/step's customData) — that id is your durable pointer; you
   don't need to duplicate the clinical payload elsewhere.
5. **Read it back through the relationship, not by re-running extraction.** The record's structured
   payload lives on a related entity your query can traverse directly — `/api/v2/query` with a
   `relationships` clause reaches it in one round trip, so a later screen never needs to re-call the
   external vendor to see what was already filed.

## Minimal example

```ts
import { callApi, runQueryRows, getRelated } from "@/lib/api"

type EncounterClassification = "Unknown" | "Inpatient" | "Outpatient" | "Both inpatient and outpatient"
function toEncounterClassification(value: unknown): EncounterClassification {
  const s = typeof value === "string" ? value.trim().toLowerCase() : ""
  if (s === "outpatient" || s === "office_visit") return "Outpatient"
  if (s === "inpatient") return "Inpatient"
  return "Unknown" // never guess a clinical classification you can't support
}

function parseRejectedDefinitions(detail: string): string[] {
  const m = /names? not found:\s*\[([^\]]*)\]/i.exec(detail)
  return m ? m[1].split(",").map((s) => s.replace(/"/g, "").trim()) : []
}

export async function attachExternalRecord(
  personId: number,
  input: { name: string; fileId: number; entries: Array<Record<string, unknown>> },
) {
  let entries = input.entries.map((e) =>
    "encounterClassification" in e
      ? { ...e, encounterClassification: toEncounterClassification(e.encounterClassification) }
      : e,
  )
  let typeName: string | undefined = "Discharge Summary" // an ambition, not a guarantee

  for (let attempt = 0; attempt < 3; attempt++) {
    const body = new FormData()
    body.append("request", JSON.stringify({
      name: input.name, fileId: input.fileId, exportDate: new Date().toISOString(),
      careQualityDataList: entries,
      ...(typeName ? { medicalRecordType: { name: typeName } } : {}),
    }))
    const res = await callApi<{ id: number }>(
      "record/attach", `/api/v2/person/${personId}/medical-record`, { method: "POST", body },
    )
    if (res.success) return res

    if (typeName && /medical record type not found/i.test(res.error ?? "")) {
      typeName = undefined // retry untyped — the data still reaches the chart
      continue
    }
    const rejected = parseRejectedDefinitions(res.error ?? "")
    if (rejected.length) {
      entries = entries.filter((e) => !rejected.includes(String((e as any).name)))
      continue
    }
    return res // a different failure — don't loop forever
  }
}

// Read it back later without re-running extraction.
export async function readAttachedRecord(recordId: number) {
  const rows = await runQueryRows({
    key: "MedicalRecordDocument",
    attributes: ["id", "name"],
    filter: `id==${recordId}`,
    relationships: [{
      key: "MedicalRecordDocument.MedicalRecordDocumentProvidesCareQualityData.CareQualityData",
      attributes: ["id", "data"],
    }],
  })
  return rows.flatMap((r) =>
    getRelated(r, "MedicalRecordDocument.MedicalRecordDocumentProvidesCareQualityData.CareQualityData"),
  )
}
```

## Gotchas

- **One unrecognized value 400s the *whole* record**, silently discarding every field that would
  have attached cleanly — always parse-and-retry rather than treating the whole payload as invalid.
- **A declared record "type" resolves against a closed, tenant-specific vocabulary** maintained
  upstream — treat it as best-effort and retry untyped on rejection instead of failing the attach.
- **Don't re-upload a binary you already have a file id for** — pass the existing file id so the
  same document isn't stored twice.
- **The related clinical-data entity may arrive as an object, a JSON string, or an array** depending
  on path — parse defensively the same way you do for `customData`.
- **Partial failure across multiple documents in one case is normal** — attach each independently
  and report per-document success/failure rather than aborting the batch on the first error.

## Related

- [results-ingestion.md](results-ingestion.md) — the purpose-built family for lab/test results
  specifically; prefer it over this generic attach when that's what you're recording.
- [deferred-record-creation.md](deferred-record-creation.md) — creating the Person this record
  attaches to.
- [closed-vocabulary-writes.md](closed-vocabulary-writes.md) — the general parse-400-and-retry
  idiom.
- [query-the-data-graph.md](query-the-data-graph.md) — the relationship read-back.
- [deidentify-before-external-ai.md](deidentify-before-external-ai.md) — if this data is headed to
  a third party first.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
