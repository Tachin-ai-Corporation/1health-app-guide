# Preview a step's runtime rendering with no journey or order

**Use when:** you're building template-authoring tooling and want to show "what will this step look
like to the end user" — e.g. a live preview pane next to a step editor — without creating a real
order or journey.
**Routes:** `GET /api/v2/health/workflow-template/{id}/step/{stepId}/configuration` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-template/_id_/step/_stepId_/configuration/agents.md) — the ONLY call preview needs; no journey/order id and no submit call are involved.
**Reference code:** none public — see the Minimal example.
**Seen in:** 1health platform usage

## Pattern

1. **Feed the same rendering logic a template configuration instead of a live journey's step-info.**
   Reuse the exact component/dispatch you already use for a running step (see
   [dynamic-step-fields.md](dynamic-step-fields.md)), sourced from `GET .../configuration` — no
   journey or order needs to exist.
2. **Treat every field the live path would normally supply — org, patient, status, submitted
   values — as absent and optional.** Preview genuinely doesn't have them; code that dereferences a
   nested live-only field directly (instead of optional-chaining) crashes specifically in preview,
   which makes it an easy gap to miss if you only test the live path.
3. **Simulate "submit" entirely client-side.** Write fabricated status/timestamp/answer data into
   local UI state to flip from an edit form to a "completed" view, and never call the real submit
   endpoint.
4. **This is unrelated to template structural validation.** Preview is about one step's runtime
   appearance; whether the whole template graph is well-formed is a separate concern handled at
   publish time (see [template-versions-draft-publish.md](template-versions-draft-publish.md)).

## Minimal example

```ts
import { fetchStepConfiguration, fetchStepInfo, submitStepFields } from "@/lib/api"

// Live: journeyId is defined. Preview: journeyId is undefined. Same downstream renderer either way.
async function loadStepForRender(templateId: number, stepId: number, journeyId?: number) {
  const configuration = journeyId
    ? (await fetchStepInfo(journeyId, stepId)).data?.configuration
    : (await fetchStepConfiguration(templateId, stepId)).data   // preview: config only, no instance

  return { configuration, journeyId }
}

function submitStep(journeyId: number | undefined, stepId: number, fields: unknown[], values: Record<string, unknown>) {
  if (journeyId === undefined) {
    // Preview: local state only, no network call.
    return { status: "Completed", submittedAt: new Date().toISOString(), values }
  }
  return submitStepFields(journeyId, stepId, fields, values)   // live: the real submit
}
```

## Gotchas

- **No network call happens on "submit" in preview** — if one fires, the live submit path got
  wired in by mistake.
- **Defensive/optional field access is required here, not a nice-to-have** — preview supplies
  strictly less data than any real journey ever would.

## Related

- [dynamic-step-fields.md](dynamic-step-fields.md) — the field-rendering logic this recipe reuses
  unchanged.
- [template-versions-draft-publish.md](template-versions-draft-publish.md) — the draft this
  preview's configuration is read from.
- [workflows-journeys-steps.md](workflows-journeys-steps.md) — the live counterpart this recipe
  deliberately avoids calling.
