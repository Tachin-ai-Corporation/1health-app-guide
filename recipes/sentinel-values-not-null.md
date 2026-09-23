# Read unset and encoded values correctly ("n/a", -1, "true_")

**Use when:** you read attributes off platform records (to render empty states, validate, compare,
filter, or sort), or you need to clear an optional field you previously set.
**Routes:** `POST /api/v2/query` → [agents.md](https://agents.1health.io/public/prod/api/v2/query/agents.md) · `GET /api/v3/patient/{id}` · `PATCH /api/v3/patient/{id}` → [agents.md](https://agents.1health.io/public/prod/api/v3/patient/agents.md) · grid views `POST /api/v3/health/grid/<view>` → [manifest](https://agents.1health.io/public/prod/api/manifest.md)
**Reference code:** none public — see the Minimal example
**Seen in:** 1health platform usage (every rule below confirmed against the demo environment)

## Pattern

1. **Expect a placeholder, not `null`.** On a freshly created record:
   - unset **text** comes back as the literal string `"n/a"` (not `null`, not `""`);
   - unset **integers** come back as `-1`;
   - **coded** (value-list) fields are `"n/a"` when unset, or their default (e.g. `"Unknown"` for
     `gender`, `sexAtBirth`, `race`, `ethnicity` on a v3 patient).
   Schema metadata uses the same convention (`"n/a"` for "none", `-1` for "no limit").
2. **`/v2/query` encodes some types.** It returns **BOOLEAN** attributes as the *strings* `"true_"`
   and `"false_"` (trailing underscore), and **coded** attributes as *arrays* — `["Unknown"]`,
   `["n/a"]`. The typed v3 routes (e.g. `GET /api/v3/patient/{id}`) return plain values instead.
3. **Filters use plain literals, not the encoded form.** In a `/query` RSQL filter, `enabled==false`
   matches; `enabled==false_` matches nothing.
4. **Clear a field by sending `"n/a"`.** The v3 patient routes document `"n/a"` as the way to clear an
   optional field, and to reset a coded field to its default. Some fields (legal names, date of birth,
   last-4 SSN) can't be cleared at all.
5. **Normalize once, at the edge.** Decode every value in one shared row-mapping helper — placeholders
   → `undefined`, `"true_"`/`"false_"` → booleans, coded arrays → their single value — and never
   scatter these checks across screens. Run grid rows through the same helper.
6. **An attribute you didn't request is absent, not unset.** `/v2/query` returns only the attributes
   you list; with none listed, rows carry no attributes at all.

## Primary vs fallback

- **Primary — the typed route for the resource** (e.g. `GET /api/v3/patient/{id}`) when one exists:
  it returns plain booleans and plain coded values, so there's less to decode.
- **Fallback — `/v2/query`** when you need projections, filters, or relationships the typed route
  doesn't offer: decode its values with the helper below.

## Minimal example

```ts
const UNSET = "n/a"

/** One place that decides what "empty" means for platform values. */
export function readOptional<T>(value: T | null | undefined): T | undefined {
  if (value === null || value === undefined) return undefined
  if (typeof value === "string" && value.trim().toLowerCase() === UNSET) return undefined
  if (typeof value === "number" && value === -1) return undefined // unset integer
  return value
}

/** /v2/query returns BOOLEANs as "true_" / "false_". */
export function readBool(value: unknown): boolean | undefined {
  if (typeof value === "boolean") return value
  if (value === "true_" || value === "true") return true
  if (value === "false_" || value === "false") return false
  return undefined
}

/** /v2/query returns coded (value-list) fields as arrays, e.g. ["Unknown"] or ["n/a"]. */
export function readCoded(value: unknown): string | undefined {
  const single = Array.isArray(value) ? value[0] : value
  return readOptional(typeof single === "string" ? single : undefined)
}

// Filtering: plain literals, not the encoded form.
const filter = "enabled==false" // NOT "enabled==false_"

// Clearing via the v3 patient route: a blanked form field becomes "n/a".
export const toPatientPatch = (form: { middleName?: string }) => ({
  middleName: form.middleName?.trim() || UNSET,
})
```

## Gotchas

- **`"n/a"` and `"false_"` are truthy.** A naive `if (value)` treats an unset field as set and a
  `false` boolean as `true`; a raw render shows "n/a" or "false_" to your users.
- **`-1` isn't always "unset".** It's the sentinel for integers that were never set; if a field can
  legitimately hold negative numbers, check its schema before treating `-1` as empty.
- **Sorting and filtering see placeholders as real values.** Exclude them before sorting a column
  client-side, or they cluster together.
- **Free-text collisions.** If users can type into a field, a person who literally types "N/A" is
  indistinguishable from unset — decide that policy once, in the helper.
- **To clear, use the documented `"n/a"`** rather than `""` or `null`.

## Related

- [patient-crud.md](patient-crud.md) — the v3 patient create/update routes with plain values.
- [query-the-data-graph.md](query-the-data-graph.md) — `/query` returns only the attributes you ask for.
- [grid-list-views.md](grid-list-views.md) — map grid rows through the same helper.
- [schema-discovery.md](schema-discovery.md) — check an attribute's declared type before decoding it.
