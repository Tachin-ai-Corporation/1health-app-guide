# Admin-defined typed custom fields

**Use when:** you need typed, named, admin-configurable fields on a business-object type — so a tenant admin can add a field through a UI without a code deploy, and the field carries an explicit type instead of "whatever shape you put in a JSON blob."
**Routes:** `GET /v3/custom-data/available-types` · `GET/POST/DELETE /v3/custom-data/definition[/{id}]` · `DELETE /v3/custom-data/field/{id}` · `GET/PATCH /v3/custom-data/instance/{id}` → [manifest](https://agents.1health.io/public/prod/api/manifest.md) (confirm exact doc paths there)
**Reference code:** [`lib/api/custom-fields.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/api/custom-fields.ts) · [`lib/custom-field-resolution.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/custom-field-resolution.ts#L70)
**Seen in:** patient-vault (the only example app using this mechanism)

## Pattern

1. This is a **structurally different mechanism from schemaless `customData`** ([read-write-custom-data.md](read-write-custom-data.md)): you first define named, typed fields against a business-object type, then read/write typed *values* per instance. Reach for it when you want admin-managed schema rather than developer-managed JSON shape.
2. Discover which types support typed custom fields via the available-types endpoint, and resolve your target type's numeric id from its string key.
3. Define a **field group**: a name, the target type's numeric id, and an array of fields, each with a `displayName`, a `fieldType` (`TEXT`/`INTEGER`/`DECIMAL`/`DATE`/`TIMESTAMP`/`JSON`), and optionally a `jsonSchema`.
4. Per instance, read every defined value with one call — only fields that currently **have** a value come back — and write or clear values with a single `PATCH` (send `null` to clear a field).
5. Match a field by its **definition name + `displayName`**, never by a raw numeric field id hardcoded in your app — ids are assigned when the definition is created and differ per tenant/environment.
6. Handle deletion at both levels: dropping one field vs. dropping the whole definition it belongs to.

## Minimal example

```ts
import { callApi } from "@/lib/api"

type FieldType = "TEXT" | "INTEGER" | "DECIMAL" | "DATE" | "TIMESTAMP" | "JSON"
interface CustomFieldDefinition {
  id: number; boClassId: number; name: string
  fields: Array<{ id: number; displayName: string; fieldKey: string; fieldType: FieldType }>
}
const withApp = (path: string) => `${path}?appId=${appId}`

// Discover the target type's numeric id (once).
const types = await callApi<{ id: number; key: string }[]>("customFields/types", "/api/v3/custom-data/available-types")
const personTypeId = types.data?.find((t) => t.key === "Person")?.id

// Define a typed field group against that type.
const definition = await callApi<CustomFieldDefinition>("customFields/define", withApp("/api/v3/custom-data/definition"), {
  method: "POST",
  body: JSON.stringify({
    name: "Demographics extras",
    boClassId: personTypeId,
    fields: [{ displayName: "Preferred pharmacy", fieldType: "TEXT" }],
  }),
})

// Resolve a field by definition + displayName — never hardcode its numeric id.
function findField(defs: CustomFieldDefinition[], displayName: string) {
  for (const def of defs) {
    const field = def.fields.find((f) => f.displayName === displayName)
    if (field) return field
  }
}

// Read every defined value currently set on one instance.
const values = await callApi<Record<string, unknown>>("customFields/readInstance", withApp(`/api/v3/custom-data/instance/${personId}`))

// Write (or clear, via null) a value. Field keys must belong to the
// instance's own business-object class or the write is rejected.
const field = findField([definition.data!], "Preferred pharmacy")!
await callApi("customFields/writeInstance", withApp(`/api/v3/custom-data/instance/${personId}`), {
  method: "PATCH",
  body: JSON.stringify({ [field.fieldKey]: "Main St. Pharmacy" }),
})
```

## Gotchas

- Don't confuse this with the schemaless `customData` blob — they're two independent mechanisms on the same platform, and this one may exist in some environments and not others (a 404 here commonly means "not deployed yet," not "no data" — see [environment-capability-detection.md](environment-capability-detection.md)).
- Resolve fields by **definition name + `displayName`**, never by a numeric `id`/`fieldKey` hardcoded in your app.
- A `PATCH` on an instance only accepts field keys that belong to that instance's own business-object class — writing a field defined against the wrong type is rejected.
- A field just created may not be immediately visible to the very next read — treat this as a [read-after-write-consistency.md](read-after-write-consistency.md) case and poll-with-backoff rather than reading once and giving up.
- The instance read only returns fields that currently **have** a value — a field with no value set is simply absent from the response, not present-with-null.

## Related

- [read-write-custom-data.md](read-write-custom-data.md) — the schemaless alternative; use it when fields don't need admin-defined structure.
- [read-after-write-consistency.md](read-after-write-consistency.md) — poll-with-backoff after defining or writing a field.
- [environment-capability-detection.md](environment-capability-detection.md) — treat a 404 from this API family as "not deployed here."
- [../api/README.md](../api/README.md)
