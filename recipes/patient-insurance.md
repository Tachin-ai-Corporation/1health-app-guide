# Read and write patient insurance from the right scope

**Use when:** your app captures or displays a patient's insurance — as the patient themself, as an
org acting on a named patient, or as part of an in-progress order — and you need closed-enum-valid
records rather than free-form fields.
**Routes:** `GET/POST/PUT /api/v2/health/patient/insurance` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/patient/insurance/agents.md) · `POST/PUT/DELETE /api/v2/organization/patient/{patientId}/insurance` → [agents.md](https://agents.1health.io/public/prod/api/v2/organization/patient/_patientId_/insurance/agents.md) · `GET /api/v2/organization/patient/{patientId}/insurance/list` → [agents.md](https://agents.1health.io/public/prod/api/v2/organization/patient/_patientId_/insurance/list/agents.md) · `GET/POST /api/v2/health/order/{orderId}/patient/{patientId}/insurance` and `PUT …/insurance/{insuranceId}` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/order/_orderId_/patient/_patientId_/insurance/agents.md) · `DELETE /api/v2/health/insurance/{insuranceId}` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/insurance/agents.md) · `GET /api/v2/health/insurance/{insuranceId}/patient/{patientId}/file/{fileId}/download` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/insurance/_id_/patient/_patientId_/file/_fileId_/download/agents.md)
**Reference code:** none public — see the Minimal example
**Seen in:** 1health platform usage

## Pattern

1. Pick the scope that matches who's authenticated and what you already hold — these are three
   separate CRUD families, not interchangeable views of one endpoint:
   - **Self-service** (`/api/v2/health/patient/insurance`) — the logged-in patient manages their
     own insurance; no patient id in the path, it's inferred from the session.
   - **Org-context** (`/api/v2/organization/patient/{patientId}/insurance[/list]`) — staff acting
     on a named patient they can see.
   - **Order-context** (`/api/v2/health/order/{orderId}/patient/{patientId}/insurance`) —
     capturing insurance as part of an in-progress order step.
2. Validate against the platform's closed enums before sending — they're fixed, not
   tenant-configurable, so there's no discovery call: `insuranceType`
   (`MEDICAL`/`DENTAL`/`HOSPICE`/`VISION`), `insurancePrecedence`
   (`PRIMARY`/`SECONDARY`/`SUPPLEMENTAL`/`OTHER`), `relationshipToInsured`
   (`SELF`/`SPOUSE`/`PARENT`/`CHILD`/`DEPENDENT`).
3. Only send a `subscriber` (the policy holder) when `relationshipToInsured` isn't `SELF`.
4. Download an insurance card image through its own scoped route — by insurance id + patient id +
   file id — rather than the platform's generic file-download-by-id route.
5. Delete through the standalone `DELETE /api/v2/health/insurance/{insuranceId}` regardless of
   which scope created the record.

## Minimal example

```ts
import { authFetch, getOneHealthBaseUrl } from "@/lib/auth-client"

type InsuranceType = "MEDICAL" | "DENTAL" | "HOSPICE" | "VISION"
type InsurancePrecedence = "PRIMARY" | "SECONDARY" | "SUPPLEMENTAL" | "OTHER"
type RelationshipToInsured = "SELF" | "SPOUSE" | "PARENT" | "CHILD" | "DEPENDENT"

interface InsuranceWrite {
  memberIdNumber: string
  insuranceType: InsuranceType
  insurancePrecedence: InsurancePrecedence
  relationshipToInsured: RelationshipToInsured
  insuranceOrganizationDTO: { id: number }
  subscriber?: { firstName: string; lastName: string; dob: string }  // required unless SELF
}

// SELF-SERVICE — the logged-in patient's own insurance; no patientId in the path.
async function addOwnInsurance(insurance: InsuranceWrite) {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/v2/health/patient/insurance`, {
    method: "POST",
    body: JSON.stringify(insurance),
  })
  if (!response.ok) throw new Error(`Create failed: ${response.status}`)
}

// ORG-CONTEXT — staff acting on a named patient. Read is a distinct `/list` route.
async function addPatientInsurance(patientId: number, insurance: InsuranceWrite) {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/v2/organization/patient/${patientId}/insurance`, {
    method: "POST",
    body: JSON.stringify(insurance),
  })
  if (!response.ok) throw new Error(`Create failed: ${response.status}`)
}

async function listPatientInsurance(patientId: number) {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/v2/organization/patient/${patientId}/insurance/list`)
  if (!response.ok) throw new Error(`Fetch failed: ${response.status}`)
  return response.json()
}

// ORDER-CONTEXT — capturing insurance mid-order. Update takes the insurance id in the path.
async function addOrderInsurance(orderId: number, patientId: number, insurance: InsuranceWrite) {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(
    `${baseUrl}/api/v2/health/order/${orderId}/patient/${patientId}/insurance`,
    { method: "POST", body: JSON.stringify(insurance) },
  )
  if (!response.ok) throw new Error(`Create failed: ${response.status}`)
}

async function updateOrderInsurance(
  orderId: number, patientId: number, insuranceId: number, insurance: InsuranceWrite,
) {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(
    `${baseUrl}/api/v2/health/order/${orderId}/patient/${patientId}/insurance/${insuranceId}`,
    { method: "PUT", body: JSON.stringify(insurance) },
  )
  if (!response.ok) throw new Error(`Update failed: ${response.status}`)
}
```

## Gotchas

- **The three scopes are separate CRUD families, not interchangeable** — the org- and
  order-context variants take an explicit `patientId` (and, for order-context, `orderId`) that the
  self-service variant infers from the caller's own session; a client built against one scope
  won't work against another without changes.
- **The org-context read is a distinct `/insurance/list` route**, not a bare GET on the write path
  — don't assume the write path also serves reads.
- **The order-context update puts the insurance id in the path** (`PUT …/insurance/{insuranceId}`),
  unlike its GET/POST siblings — don't send the update to the collection path.
- **`subscriber` is required the moment `relationshipToInsured` isn't `SELF`** — validate this
  client-side before submitting, since the platform enforces it server-side too.
- **Insurance card images have their own download route** (insurance id + patient id + file id) —
  the platform's generic file-download-by-id route isn't it.

## Related

- [patient-crud.md](patient-crud.md) — the patient record this insurance hangs off.
- [orders-and-master-orders.md](orders-and-master-orders.md) — the order an in-progress insurance
  capture belongs to.
- [attachments.md](attachments.md) — the platform's generic file/download mechanism this
  deliberately doesn't use.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
