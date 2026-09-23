# Treat "n/a" as unset, not null

**Use when:** you read optional fields off platform records (to render empty states, validate,
compare, or sort), or you need to clear an optional field you previously set.
**Routes:** `GET /api/v3/patient/{id}` · `PATCH /api/v3/patient/{id}` → [agents.md](https://agents.1health.io/public/prod/api/v3/patient/agents.md) · grid views `POST /api/v3/health/grid/<view>` → [manifest](https://agents.1health.io/public/prod/api/manifest.md)
**Reference code:** none public — see the Minimal example
**Seen in:** 1health platform usage (confirmed against the demo environment)

## Pattern

1. **Expect a placeholder, not `null`.** An optional text field that was never set comes back as the
   literal string `"n/a"` — for example `middleName`, `genderIdentity`, and `preferredLanguage` on a
   freshly created v3 patient. It is not `null`, and not `""`.
2. **Coded fields default to a value, not to empty.** Fields with an allowed-value list (e.g.
   `gender`, `sexAtBirth`, `race`, `ethnicity` on a v3 patient) default to `"Unknown"` when not
   provided.
3. **Clear a field by sending `"n/a"`.** The v3 patient routes document `"n/a"` as the way to clear an
   optional field, and as the way to reset a coded field to its default. Some fields (legal names,
   date of birth, last-4 SSN) can't be cleared at all.
4. **Normalize once, at the edge.** Map `"n/a"` → `undefined` in one shared row-mapping helper when you
   read, and map "user cleared this" → `"n/a"` when you write — never scatter the check across screens.
5. **Grids can surface `"n/a"` too.** Run grid rows through the same helper before rendering, comparing,
   or exporting.
6. **An attribute you didn't request is absent, not unset.** `POST /api/v2/query` returns only the
   attributes you list; with none listed, rows carry no attributes at all. Don't read absence as "blank".

## Minimal example

```ts
const UNSET = "n/a"

/** One place that decides what "empty" means for platform values. */
export function readOptional<T>(value: T | typeof UNSET | null | undefined): T | undefined {
  if (value === null || value === undefined) return undefined
  if (typeof value === "string" && value.trim().toLowerCase() === UNSET) return undefined
  return value as T
}

/** Build a v3 patient patch where a blanked form field clears the stored value. */
export function toPatientPatch(form: { middleName?: string; preferredLanguage?: string }) {
  return {
    middleName: form.middleName?.trim() || UNSET,
    preferredLanguage: form.preferredLanguage?.trim() || UNSET,
  }
}

// Rendering: readOptional(patient.middleName) ?? "—"
```

## Gotchas

- **`"n/a"` is truthy.** A naive `if (value)` treats an unset field as set, and a raw render shows the
  string "n/a" to your users.
- **Sorting and filtering see it as a real value.** Exclude placeholder rows before sorting a column
  client-side, or they cluster together as the string "n/a".
- **Free-text collisions.** If users can type into a field, a person who literally types "N/A" is
  indistinguishable from unset — decide that policy once, in the helper.
- **Don't assume `null` for numbers and dates either.** Check a real record of that type before you
  write empty-state logic for its non-text fields.
- **To clear, use the documented `"n/a"`** rather than `""` or `null` — the docs define the former.

## Related

- [patient-crud.md](patient-crud.md) — the v3 patient create/update routes this applies to.
- [grid-list-views.md](grid-list-views.md) — map grid rows through the same helper.
- [query-the-data-graph.md](query-the-data-graph.md) — `/query` returns only the attributes you ask for.
