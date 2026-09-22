# Resolve a workflow step's fields dynamically

**Use when:** you're rendering or filling in a step's form fields and need to find the right field
to read/write **without hardcoding a per-environment id** — the common case any time you touch a
step's dynamic fields at all.
**Routes:** `GET /api/v2/journey/{id}/step/{stepId}/info` → [agents.md](https://agents.1health.io/public/prod/api/v2/journey/_id_/step/_stepId_/info/agents.md) (the running instance) — or, before a journey exists, `GET /api/v2/health/workflow-template/{templateId}/step/{stepId}/configuration` → [route docs](https://agents.1health.io/public/prod/api/manifest.md). Resolution itself is a client-side helper, not a route.
**Reference code:** [`lib/api/workflow-template.ts`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/lib/api/workflow-template.ts) · [`lib/api/container-journeys.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-secure-share/blob/main/lib/api/container-journeys.ts) (resolve-by-type variant)
**Seen in:** most example apps (template baseline; secure-share resolves by type)

## Pattern

1. **A step's fields are data, not code.** Labels, types, options, and each field's
   per-environment `fieldIdentifier` (a GUID) all come back at runtime from the step's
   configuration — never hardcode a `fieldIdentifier`; it differs per tenant/environment.
2. **Fetch the field list** from wherever you have it: `fetchStepInfo` on a running journey step
   (schema + current values), or the template's own step configuration before a journey exists.
   Both shapes nest the same array at `configuration.metadata.dynamicFields.custom.fields`.
3. **Resolve by label — the stable, human-authored name.** Pass a map of
   `{ localName: "Exact Label" }`; get back `{ localName: fieldIdentifier | undefined }`. This is
   THE way to avoid hardcoding GUIDs.
4. **Resolve by type when there's no reliable label to key off** (e.g. you only know "the file
   field" or "the one checkbox group," not its exact admin-editable label): find the field whose
   `type` matches (`"fileUpload"`, `"customField.select.checkboxes"`, …). Only safe when the step
   has at most one field of that type.
5. **Render generically**, dispatching on `field.type` rather than hand-coding one component per
   step — a text input, date input, dropdown/checkbox group sourced from `options`, a file input,
   or (for `customText`) read-only help text with no input at all.
6. **Submit using the resolved id(s)** via the matching [step-submit recipe](workflows-journeys-steps.md#submitting-a-step--three-recipes)
   — echoing the full field array back, mutating only the field(s) whose id you resolved.

## Minimal example

```ts
import { fetchStepInfo, getDynamicFields, resolveFieldsByLabel } from "@/lib/api"

const info = await fetchStepInfo(journeyId, stepId)
const fields = getDynamicFields(info.data?.configuration)

// Resolve by LABEL (preferred): stable across environments.
const ids = resolveFieldsByLabel(fields, { evidence: "Upload Evidence", note: "Clinical Note" })

// Resolve by TYPE (fallback): when there's one field of a type and no stable label to key off.
const fileField = fields.find((f) => f.type === "fileUpload")
```

## Gotchas

- **Never hardcode a `fieldIdentifier`** — it's a per-environment GUID assigned when the template
  is cloned/published, not a stable name; hardcoding it breaks the moment your app installs on a
  new tenant or the template gets rebuilt.
- **Type-based resolution only works when a step has one field of that type.** Two dropdowns on
  the same step can't be told apart by type — fall back to label matching, or a positional
  convention you control, instead.
- **The submit is a full echo, not a patch** — resolve fields from the SAME fetch you're about to
  submit against; mixing a field list fetched from the template with a submit against a live
  journey step risks omitting a field the journey actually has.
- **`options` values are the literal wire values** the backend expects on submit — for a
  dropdown/checkbox field, submit the option's value verbatim, not a UI-only display label.
- **`customText` fields have no submittable value** — they're read-only help text; skip them when
  building your submit payload.

## Related

- [workflows-journeys-steps.md](workflows-journeys-steps.md) — where these resolved ids get
  submitted, and the three submit recipes.
- [resolve-actionable-step.md](resolve-actionable-step.md) — picking *which* step to resolve
  fields for when you don't have a running journey to ask.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md).
