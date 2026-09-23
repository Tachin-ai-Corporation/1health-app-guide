# Deferred patient/medical-record creation

**Use when:** your app collects or derives patient identity and clinical data over a multi-step
flow (intake, extraction, review) *before* it's certain the case will proceed — and you want to
avoid creating throwaway or duplicate patient records for every abandoned draft.
**Routes:** `POST /v3/patient` → [agents.md](https://agents.1health.io/public/prod/api/v3/patient/agents.md) · `POST /v2/person/upsert` → [agents.md](https://agents.1health.io/public/prod/api/v2/person/upsert/agents.md) · `POST /v2/person/{id}/medical-record` → [route docs](https://agents.1health.io/public/prod/api/manifest.md) · step commit via `POST /v2/journey/{id}/step/{stepId}/submit` → [agents.md](https://agents.1health.io/public/prod/api/v2/journey/_id_/step/_stepId_/submit/agents.md)
**Reference code:** [`lib/expertdx/patient.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/lib/expertdx/patient.ts)
**Seen in:** expertdx · 1health platform usage (staged-file flush)

## Pattern

1. **Keep everything before the point of commitment in your own draft state** (customData or
   component state) — never create a platform Person "just in case." Only write to the platform the
   moment a human action makes the record real (an order submission, a signed intake) — the point
   past which the draft can no longer just be discarded.
2. **Create the patient at commit with the v3 patient create — then confirm it's attached to your
   organization.** Run a scored find first ([patient-find.md](patient-find.md)), create with
   `POST /api/v3/patient`, and immediately do one org-scoped read of the new patient. A person that
   isn't attached to your organization is invisible to the rest of the platform (workflow steps that
   bind to a patient, medical-record reads), so this check is not optional bookkeeping. If the
   platform reports the person isn't a patient of your context organization, create through the
   person upsert with its explicit org-attach flag instead (see Primary vs fallback).
3. **On the upsert fallback, never send the fields that let it match an existing person** (typically email/phone)
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
7. **For file attachments specifically**, staging them client-side (grouped by attachment
   type/purpose) is the file-shaped version of step 1's draft state: hold the raw `File` objects in
   memory, and only flush each group through the normal upload call
   ([attachments.md](attachments.md)) once the parent record's id comes back from its own create
   call — clearing that group's staging entry as it flushes so re-running the flow can't re-upload
   the same file.

## Primary vs fallback

- **Primary — `POST /api/v3/patient`:** the current create-a-patient API (a scored find first, an
  org-attachment check right after).
- **Fallback — `POST /api/v2/person/upsert` with `markAsPatientToContextOrganization: true`:** switch
  when the new patient isn't visible in your organization's context — the check, or the next step,
  returns "… is not patient of context organization" or "Person with id: N not found" — or when you
  specifically want upsert's create-or-find behavior.

## Minimal example

```ts
import { callApi } from "@/lib/api"

// PRIMARY — called ONLY at the point of commitment (e.g. order submission), never during
// intake/review, so an abandoned draft never becomes an orphaned patient record.
export async function createPatientAtCommit(input: { firstName: string; lastName: string; dob: string }) {
  return callApi<{ id: number }>("patient/create", "/api/v3/patient", {
    method: "POST",
    body: JSON.stringify(input), // dob is YYYY-MM-DD; then confirm org attachment before continuing
  })
}

// FALLBACK — when the created patient isn't attached to your organization.
export async function createPersonAtCommit(input: { firstName: string; lastName: string; birthDate: string }) {
  return callApi<{ id: number }>("person/upsert", "/api/v2/person/upsert", {
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
  return callApi<{ id: number }>("person/attachRecord", `/api/v2/person/${personId}/medical-record`, {
    method: "POST", body,
  })
}

// If a later step 400s with "Person with id: N not found" or "... is not patient of context
// organization", the person isn't attached to your organization — use the upsert fallback.
```

## Gotchas

- **Confirm the new patient is attached to your organization.** An example app found that a
  `POST /v3/patient` create could leave the person unattached, so every workflow step or
  medical-record read expecting a patient of the *context organization* 400'd. Check right after
  create; if it isn't attached, use the upsert fallback with its explicit org-attach flag.
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
- **Staged files are memory-only** — they don't survive a page reload, so a flow that can be
  abandoned mid-way and resumed later needs a separate durable plan for attachments; don't assume
  the same drafting approach that works for form fields (e.g. customData) also covers files.

## Related

- [patient-crud.md](patient-crud.md) — once a person exists, this is how you manage it.
- [attachments.md](attachments.md) — the upload call each staged file group flushes through.
- [external-record-to-medical-record.md](external-record-to-medical-record.md) — the record-attach
  step in more detail.
- [closed-vocabulary-writes.md](closed-vocabulary-writes.md) — the parse-the-400-and-retry idiom.
- [deidentify-before-external-ai.md](deidentify-before-external-ai.md) — this pattern is often the
  *last* step of a pipeline that starts there.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
