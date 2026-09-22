# Resolve a campaign's base template and target step

**Use when:** you need to find a step's live configuration or identity **reliably across any org**
running your campaign — not just the org that created it — e.g. reading/writing step-level
notification config that must resolve to the same step no matter who's asking, or locating "the
step that does X" in a template whose step names you don't fully control.
**Routes:** `POST /api/v2/query` (×2, structural) → [agents.md](https://agents.1health.io/public/prod/api/v2/query/agents.md)**Reference code:** [`lib/api/step-resolution-core.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-secure-share/blob/main/lib/api/step-resolution-core.ts)
**Seen in:** secure-share

## Pattern

1. **Don't trust a tenant-scoped convenience field** for "the" base template (e.g. a shared
   campaign/container payload's own `baseWorkflowTemplate.id` attribute) — depending on whose copy
   of the payload you're reading, it can be a stale or plain wrong cross-org snapshot.
2. **Resolve it through the canonical relationship instead.** Query the campaign by id and
   eager-load `WorkflowCampaign.WorkflowCampaignHasBaseWorkflowTemplate.WorkflowTemplate`, then
   read the related template's id off the response. This is tenant-independent: every org that can
   read the campaign gets back the SAME base template — the one new journeys actually clone from.
3. **Walk the step tree from that template id** with a second structural query: the root step via
   `WorkflowTemplate.WorkflowTemplateHasRootWorkflowTemplateStep.WorkflowTemplateStep`, nested one
   level deeper for children via
   `WorkflowTemplateStep.WorkflowTemplateStepHasChildWorkflowTemplateStep.WorkflowTemplateStep`.
4. **Pick the target child by fuzzy name match, with fallbacks — never `childSteps[0]`.** Match
   case-insensitively against expected keyword(s) for what the step does; if nothing matches, fall
   back to the last child (the terminal step in a linear chain), then the first. The first child is
   commonly an intake/container step, not the one whose completion you actually care about.
5. **Treat "nothing to resolve" as a distinct outcome, not an error.** A campaign with no base
   template yet, or a template with no child steps, usually means a counterpart hasn't finished
   building their workflow — surface a friendly "not ready" state (a sentinel value) instead of a
   destructive error, but keep an actual failed query call a real error.
6. **Keep the query-building and response-parsing pure** (no I/O, no credentials) in one shared
   module, so a client-token caller and a privileged server-token caller run the identical
   resolution and can never drift apart — see the privileged-proxy note in
   [step-config-notifications-webhooks.md](step-config-notifications-webhooks.md).

## Minimal example

```ts
import { runQueryRows, eq, getRelated, getRelatedAttr } from "@/lib/api"

const REL_BASE_TEMPLATE = "WorkflowCampaign.WorkflowCampaignHasBaseWorkflowTemplate.WorkflowTemplate"
const REL_ROOT_STEP = "WorkflowTemplate.WorkflowTemplateHasRootWorkflowTemplateStep.WorkflowTemplateStep"
const REL_CHILD_STEP = "WorkflowTemplateStep.WorkflowTemplateStepHasChildWorkflowTemplateStep.WorkflowTemplateStep"

// 1. campaignId -> base WorkflowTemplate id — the CANONICAL relationship, not a
//    tenant-scoped convenience field like campaign.baseWorkflowTemplate.id.
const campaignRows = await runQueryRows({
  key: "WorkflowCampaign", filter: eq("id", campaignId), attributes: ["id"],
  relationships: [{ key: REL_BASE_TEMPLATE, attributes: ["id"], limit: 1 }],
})
const baseTemplate = getRelated(campaignRows[0], REL_BASE_TEMPLATE)[0]
const templateId = getRelatedAttr<number>(
  baseTemplate, "WorkflowCampaignHasBaseWorkflowTemplate", "WorkflowTemplate", "id",
)

// 2. templateId -> root step -> children, matched by name — never childSteps[0].
const templateRows = await runQueryRows({
  key: "WorkflowTemplate", filter: eq("id", templateId!), attributes: ["id"],
  relationships: [{
    key: REL_ROOT_STEP, attributes: ["id"], limit: 1,
    relationships: [{ key: REL_CHILD_STEP, attributes: ["id", "name"], limit: 10 }],
  }],
})
const rootWrapper = getRelated(templateRows[0], REL_ROOT_STEP)[0]
// A second level of nesting is read off the wrapper's `.instance` directly.
const children = rootWrapper?.instance.relationships?.[REL_CHILD_STEP] ?? []
const childName = (c: (typeof children)[number]) =>
  getRelatedAttr<string>(c, "WorkflowTemplateStepHasChildWorkflowTemplateStep", "WorkflowTemplateStep", "name")

const target = children.find((c) => childName(c)?.toLowerCase().includes("upload"))
  ?? children[children.length - 1]
  ?? children[0]
```

## Gotchas

- **A convenience id field scoped to one tenant's view of a shared object can silently point at
  the wrong template** for a different org — always resolve through the relationship when
  correctness must hold cross-org.
- **Never assume `childSteps[0]` is the target** — the first child is commonly an intake/container
  step; match by name with a sane fallback chain instead.
- **Name matching should be substring + case-insensitive**, since step names are admin-edited
  text, not stable identifiers — an exact match is brittle to a template redesign.
- **`getRelated`/`getRelatedAttr` are shaped for the top-level row** — a second level of nesting
  (children of a related instance) is read by indexing `wrapper.instance.relationships?.[key]`
  directly; the same prefix rules still apply to its attributes.
- **Distinguish "genuinely nothing to resolve" from "the query call failed."** Collapsing both into
  one error path hides real outages behind a friendly empty state.

## Related

- [workflows-journeys-steps.md](workflows-journeys-steps.md) — the JOURNEY-side equivalent
  (`findActionableStep` picks by its submittable flag, not by name, once you have a running
  journey).
- [step-config-notifications-webhooks.md](step-config-notifications-webhooks.md) — the config you
  typically want once you've resolved the target step.
- [provision-templates-and-campaigns.md](provision-templates-and-campaigns.md) — how the base
  template you're resolving was created.
- [query-the-data-graph.md](query-the-data-graph.md) — the underlying `/query` relationship
  mechanics (`getRelated`/`getRelatedAttr`, eager-loading).
