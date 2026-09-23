# Map a record to its id in an outside system

**Use when:** your app must remember that a 1health record (a patient, an order, an organization) is
known by a different identifier in an outside system — an EHR's MRN, a payer's member id, a vendor's
order number — and look it up in either direction.
**Routes:** `GET/POST /api/v3/external-it-system` and `GET/PUT/PATCH/DELETE …/{id}` → [agents.md](https://agents.1health.io/public/prod/api/v3/external-it-system/agents.md) · `GET/POST /api/v3/external-sys-map` and `GET/PUT/PATCH/DELETE …/{id}` → [agents.md](https://agents.1health.io/public/prod/api/v3/external-sys-map/agents.md) · list view `POST /api/v3/health/grid/external-it-system` → [agents.md](https://agents.1health.io/public/prod/api/v3/health/grid/external-it-system/agents.md)
**Reference code:** none public — see the Minimal example
**Seen in:** 1health platform usage (create, both-direction lookups, uniqueness, and delete confirmed against the demo environment)

## Pattern

1. **Register each outside system once per tenant** — `POST /api/v3/external-it-system` with a
   `name` that's unique within your tenant, plus optional `vendor`, `version`, `description`,
   `department`, `isLegacy`, and the operating `organizationId`.
2. **Map a record** — `POST /api/v3/external-sys-map` with `boInstanceId` (the 1health record),
   `externalItSystemId`, `externalId` (its id over there), and `organizationId` (the organization that
   operates that system). Optional: `type` (`mrn`, `member_id`, `npi`, `custom`, …), `sourceName`
   (where the mapping came from), and a `validFrom`/`validUntil` window (UTC; omit for open-ended).
3. **Look up in either direction** with query params on `GET /api/v3/external-sys-map`:
   platform → outside by `boInstanceId`; outside → platform by `externalItSystemId` + `externalId`.
   Add `validAt=<day>` for the mapping valid on a date; `includeExpired=true` to include expired ones.
4. **One mapping per record, organization, and system.** A second create for the same triple returns
   a 400 ("A mapping already exists …") — update the existing mapping (`PUT`/`PATCH …/{id}`) to change
   its external id.
5. **Clean up explicitly:** delete a mapping by id when the link ends; delete the system when it's
   retired.

## Primary vs fallback

- **Primary — the native `external-sys-map` record:** typed, validated, uniqueness-enforced, and
  searchable in both directions by plain query params. Use it for any identifier another app or an
  integration may also need.
- **Fallback — an external id inside your app's `customData`** (`appData.<appId>`): only for an
  app-private identifier nothing else will ever look up. Reverse lookup then depends on JSONB
  filtering, which this guide treats as unreliable for correctness
  ([read-write-custom-data.md](read-write-custom-data.md)).

## Minimal example

```ts
import { callApi } from "@/lib/api"

async function registerSystem(name: string, vendor?: string) {
  const res = await callApi<{ id: number }>("extSystem/create", "/api/v3/external-it-system", {
    method: "POST",
    body: JSON.stringify({ name, vendor }), // name must be unique within the tenant
  })
  return res.data?.id
}

async function mapRecord(input: {
  boInstanceId: number; externalItSystemId: number; externalId: string; organizationId: number; type?: string
}) {
  // Send organizationId (not organizationName) unless you intend to create an organization.
  return callApi<{ id: number }>("extMap/create", "/api/v3/external-sys-map", {
    method: "POST",
    body: JSON.stringify({ ...input, sourceName: "my-app" }),
  })
}

// Outside id -> 1health record.
async function findRecordByExternalId(externalItSystemId: number, externalId: string) {
  const qs = new URLSearchParams({ externalItSystemId: String(externalItSystemId), externalId })
  const res = await callApi<{ data: Array<{ boInstanceId: number }> }>(
    "extMap/find", `/api/v3/external-sys-map?${qs}`,
  )
  return res.data?.data?.[0]?.boInstanceId
}
```

## Gotchas

- **`organizationName` / `externalItSystemName` can create records.** When you send a name without
  the matching id, the platform resolves it by name — and creates it if it doesn't exist. Send ids
  unless creating is what you want.
- **`organizationId` is required in practice.** A mapping without it (or without `organizationName`)
  is rejected with a 400, even though the docs list both as optional.
- **An IT contact is a name *or* a person id, never both** — sending both is a 400.
- **Expired mappings are hidden by default.** A lookup that "loses" a mapping may just be past its
  `validUntil`; pass `includeExpired=true` when auditing.
- **The system registry starts empty** in a new tenant — register the system before the first mapping.

## Related

- [external-record-to-medical-record.md](external-record-to-medical-record.md) — attaching the
  clinical payload itself, as opposed to just the identifier.
- [cache-reference-data-in-custom-data.md](cache-reference-data-in-custom-data.md) — caching external
  lookups on a record.
- [read-write-custom-data.md](read-write-custom-data.md) — the customData fallback.
- [api-versions-and-layers.md](api-versions-and-layers.md) — why this lives on v3.
