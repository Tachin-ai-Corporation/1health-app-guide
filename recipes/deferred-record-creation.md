# Deferred patient/medical-record creation

**Use when:** your app collects or derives patient identity and clinical data over a multi-step
flow (intake, extraction, review) *before* it's certain the case will proceed — and you want to
avoid creating throwaway or duplicate patient records for every abandoned draft.
**Routes:** `POST /v2/person/upsert` → [agents.md](https://agents.1health.io/public/prod/api/v2/person/upsert/agents.md) · `POST /v2/person/{id}/medical-record` → [route docs](https://agents.1health.io/public/prod/api/manifest.md) · step commit via `POST /v2/journey/{id}/step/{stepId}/submit` → [agents.md](https://agents.1health.io/public/prod/api/v2/journey/_id_/step/_stepId_/submit/agents.md)
**Reference code:** [`lib/expertdx/patient.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/lib/expertdx/patient.ts)
**Seen in:** expertdx

## Pattern

1. **Keep everything before the point of commitment in your own draft state** (customData or
   component state) — never create a platform Person "just in case." Only write to the platform the
   moment a human action makes the record real (an order submission, a signed intake) — the point
   past which the draft can no longer just be discarded.
2. **Create the person with an upsert-style endpoint, not the plain "create a patient" one.** A
   plain create can produce a person unattached to any organization, which most of the platform
   (workflow steps that bind to a patient, reading medical records back) then can't see or
   reference. Explicitly attach the new person to your organization on create — this is not
   optional bookkeeping, it's what makes the record referenceable at all.
3. **Never send the fields that let upsert match an existing person** (typically email/phone)
   unless you have positively confirmed identity. Upsert's whole point is idempotent
   "create-or-find," and its match keys are documented — sending them on every intake would
   silently fold two different people's records into one chart the moment their contact info
   happened to coincide. Verify empirically, against your own tenant, what actually triggers a
   match before you rely on name+DOB alone being safe.
4. **Attach clinical data as its own record afterward**, referencing a file you already have rather
   than re-uploading it — one binary can back both a step attachment and a clinical record.
5. **Record the resulting ids** (person id, record id) back onto your workflow instance's own state
   (a step's `customData`) so the rest of the flow, and any read-back, has something durable to
   point at.
6. **Treat partial success as a first-class outcome** — one failed attachment shouldn't discard the
   person you already created or the attachments that did succeed; report failures per item and let
   the caller decide whether to retry or proceed.

## Minimal example

```ts
import { callApi } from "@/lib/api"

// Called ONLY at the point of commitment (e.g. order submission) — never during
// intake/review, so an abandoned draft never becomes an orphaned patient record.
export async function createPersonAtCommit(input: { firstName: string; lastName: string; birthDate: string }) {
  return callApi<{ id: number }>("person/upsert", "/v2/person/upsert", {
    method: "POST",
    body: JSON.stringify({
      firstName: input.firstName,
      lastName: input.lastName,
      birthDate: input.birthDate,
      // Required so workflow steps and medical-record reads can see this person at all.
      markAsPatientToContextOrganization: true,
      // NEVER send email/phoneNumber here — those are upsert's match keys, and a
      // coincidental match would silently merge this person into someone else's chart.
    }),
  })
}

export async function attachRecord(personId: number, input: { name: string; fileId: number; data: unknown[] }) {
  const body = new FormData()
  body.append("request", new Blob([JSON.stringify({
    name: input.name, fileId: input.fileId, exportDate: new Date().toISOString(),
    careQualityDataList: input.data,
  })], { type: "application/json" }))
  return callApi<{ id: number }>("person/attachRecord", `/v2/person/${personId}/medical-record`, {
    method: "POST", body,
  })
}

// THE TRAP: `POST /v3/patient` also "creates a patient", but produces a person
// unattached to any organization — later steps/reads then 400 with
// "Person with id: N not found" or "... is not patient of context organization."
// Use the upsert endpoint above instead, whenever the person must be workflow-referenceable.
```

## Gotchas

- **`POST /v3/patient` looks like the obvious "create a patient" call, but it doesn't attach the
  person to your organization** — any workflow step or medical-record read that expects a patient
  of the *context organization* then 400s. Prefer the upsert endpoint with an explicit
  organization-attach flag.
- **Sending email or phone on upsert lets the platform match an existing person** — omit them
  unless you've verified exactly what triggers a match on your tenant; a merged chart is a much
  worse failure than a duplicate one.
- **Deletion is asymmetric:** you can typically delete the person you created, but an attached
  medical record has no delete endpoint and will outlive it as an orphan — avoid creating the
  record at all rather than planning to clean it up.
- **A record "type" validates against a closed, tenant-specific vocabulary** — naming one that
  doesn't exist 400s the whole record; omit it rather than guess (see
  [closed-vocabulary-writes.md](closed-vocabulary-writes.md)).
- **This defers *platform* record creation, not user-facing state** — keep the draft itself
  somewhere durable (customData) so nothing is lost while it waits to become real.

## Related

- [patient-crud.md](patient-crud.md) — once a person exists, this is how you manage it.
- [external-record-to-medical-record.md](external-record-to-medical-record.md) — the record-attach
  step in more detail.
- [closed-vocabulary-writes.md](closed-vocabulary-writes.md) — the parse-the-400-and-retry idiom.
- [deidentify-before-external-ai.md](deidentify-before-external-ai.md) — this pattern is often the
  *last* step of a pipeline that starts there.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
