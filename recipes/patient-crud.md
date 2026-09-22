# Patient + sub-resource CRUD

**Use when:** your app manages patient/person demographic records — plus structured sub-resources
like contacts, addresses, aliases, external identifiers, and deceased status — as first-class
1health objects, not fields buried in `customData`.
**Routes:** `GET/POST/PATCH/DELETE /v3/patient[/{id}]` → [agents.md](https://agents.1health.io/public/prod/api/v3/patient/agents.md) (collection) · [route docs](https://agents.1health.io/public/prod/api/manifest.md) (item — child routes for `contact`/`address`/`alias`/`identifier`/`deceased` are listed there; confirm each exact contract via the [manifest](https://agents.1health.io/public/prod/api/manifest.md) if it isn't)
**Reference code:** [`lib/api/patient.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/api/patient.ts)
**Seen in:** patient-vault

## Pattern

1. **Model the patient as one root record plus independent sub-resource collections** hanging off
   its id — contact, address, alias, identifier, deceased — each with its own CRUD verbs at
   `/v3/patient/{id}/<subresource>[/{subId}]`. (Note the platform's schema type here is `Person`;
   the v3 REST resource is named `patient` — don't let the naming mismatch confuse a schema lookup.)
   Compose a full read by fetching the root plus every sub-resource in parallel.
2. **Normalize closed-vocabulary fields on the way out and back in.** Fields like gender,
   sexAtBirth, race, and ethnicity validate against exact, capitalized display strings server-side
   ("Black or African American", not `black_or_african_american`). Keep one map of app-code → API
   string for writes and the inverse for reads; fall back to the raw value so already-correct input
   still passes through unchanged.
3. **Never assume a sub-resource list comes back as a bare array.** Different sub-resources wrap
   their array under different keys (`contacts`, `addresses`, `content`, `items`, `data`). Write one
   `unwrapList` helper that tries each key in order and route every list read through it.
4. **Treat "not found" defensively when absence is the normal case** (e.g., no deceased record on
   file). The platform can report this via HTTP 400 while the *body* effectively says 404 —
   `{ code: 404, message: "no deceased record..." }`. Inspect the parsed body before deciding
   "doesn't exist" vs. "real error."
5. **Handle non-idempotent create-style writes defensively.** A sub-resource meant to be set once
   (marking a patient deceased) can 409 on a second POST; catch that and fall back to PATCH so a
   correction doesn't fail outright.
6. **Scope every sub-resource id to its parent.** A contact/address/alias id is only addressable
   nested under its patient id — there's no standalone `/v3/contact/{id}`.

## Minimal example

```ts
import { callApi, callApiRaw } from "@/lib/api"

// ---- closed-vocabulary normalization (write direction) ----
const SEX_TO_API: Record<string, string> = {
  male: "Male", female: "Female", intersex: "Intersex", unknown: "Unknown",
}
function mapToApi(map: Record<string, string>, value?: string | null) {
  if (!value) return undefined
  return map[value.trim().toLowerCase()] ?? value // pass already-correct input through
}

// ---- defensive list-envelope unwrap ----
function unwrapList<T>(data: unknown, ...keys: string[]): T[] {
  if (Array.isArray(data)) return data as T[]
  if (data && typeof data === "object") {
    for (const k of keys) {
      const v = (data as Record<string, unknown>)[k]
      if (Array.isArray(v)) return v as T[]
    }
  }
  return []
}

export async function listContacts(personId: string) {
  const res = await callApi<unknown>("person/listContacts", `/v3/patient/${personId}/contact`)
  return unwrapList<{ id: number; type: string; value: string }>(res.data, "contacts", "content", "items", "data")
}

export async function patchPerson(id: string, patch: { sexAtBirth?: string }) {
  return callApi("person/patch", `/v3/patient/${id}`, {
    method: "PATCH",
    body: JSON.stringify({ ...patch, sexAtBirth: mapToApi(SEX_TO_API, patch.sexAtBirth) }),
  })
}

// ---- 400-vs-404 body sniffing ----
export async function fetchDeceasedRecord(personId: string) {
  const res = await callApiRaw(`/v3/patient/${personId}/deceased`)
  const text = await res.text().catch(() => "")
  if (res.ok) return text ? JSON.parse(text) : null
  const body = (() => { try { return JSON.parse(text) } catch { return {} as any } })()
  const notFound = res.status === 404 || body.code === 404 || /no deceased record/i.test(body.message ?? "")
  if (notFound) return null
  throw new Error(body.message ?? `deceased lookup failed (${res.status})`)
}

// ---- 409-on-create -> fall back to PATCH ----
export async function setDeceased(personId: string, body: { deceasedDate: string }) {
  const created = await callApi("person/setDeceased", `/v3/patient/${personId}/deceased`, {
    method: "POST", body: JSON.stringify(body),
  })
  if (!created.success && created.statusCode === 409) {
    return callApi("person/updateDeceased", `/v3/patient/${personId}/deceased`, {
      method: "PATCH", body: JSON.stringify(body),
    })
  }
  return created
}
```

## Gotchas

- **Closed-vocabulary fields 400 on any string outside the exact display-case set** — normalize
  both directions, and keep the map data-driven so a newly accepted value is a one-line change, not
  a redeploy of every call site.
- **Sub-resource list envelopes are not uniform** — never destructure a list response directly;
  always route it through an `unwrapList`-style helper.
- **A resource whose absence is normal can arrive as HTTP 400 with an application `code` of 404 in
  the body** — read the body before raising.
- **A "set once" sub-resource write can 409 on a second attempt** — treat that as "already exists,
  correct it with PATCH," not as a hard failure.
- **Sub-resource ids are scoped to their parent patient** — always build the nested path.

## Related

- [patient-find.md](patient-find.md) — check for an existing match before creating a new patient.
- [patient-documents.md](patient-documents.md) — the attachment sub-resource, same base-path family.
- [deferred-record-creation.md](deferred-record-creation.md) — when creating a Person eagerly is
  the wrong call.
- [query-the-data-graph.md](query-the-data-graph.md) · [read-write-custom-data.md](read-write-custom-data.md)
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
