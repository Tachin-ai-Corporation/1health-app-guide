# Provision a workflow template and campaign by name

**Use when:** your app needs a specific workflow template + an active campaign to exist in a
tenant before it can do anything, and you want it to **self-install on any client account** —
idempotently, by name — instead of requiring manual per-tenant setup.
**Routes:** `GET .../workflow-template-group/list` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-template-group/list/agents.md) · `GET .../published/list` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-template-group/published/list/agents.md) · `POST .../{id}/clone` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-template-group/_id_/clone/agents.md) · `GET`/`PUT .../workflow-template/{id}` (`?setAsPublished=true`) → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-template/_id_/agents.md) · `POST .../workflow-campaign` (create) → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-campaign/agents.md) · `POST .../{id}/run` (activate) → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-campaign/_id_/run/agents.md)
**Reference code:** [`lib/api/workflow-provisioning.ts`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/lib/api/workflow-provisioning.ts) · [`lib/api/campaign.ts`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/lib/api/campaign.ts)
**Seen in:** secure-share, pcp-tcm, template

## Pattern

Each step is check-then-act, so re-running the whole flow is safe:

1. **Find a LOCAL template group by name** (tenant-owned). If found, use it.
2. **Else find a PUBLISHED (catalog) template group** by the same name and **clone** it into the
   tenant — this creates a local, tenant-owned group with a draft version.
3. **Ensure the group has a published version.** Read the group detail (`published`/`draft`
   pointers); if it's already published you're done, otherwise publish the draft (next step).
4. **Publish via the clean-node round-trip.** The publish endpoint wants a MINIMAL node shape, but
   the draft GET returns a rich one — read the draft's `rootNodes`, recursively strip each node to
   `{ id, nodeId, availableStepId, name, type, metadata, node? }` (coercing `id`/`nodeId` to
   strings), then `PUT` the whole cleaned `{ rootNodes, stickyNotes }` back with
   `?setAsPublished=true`.
5. **Create a campaign** from the now-published group — but **check for an existing one by name
   first** (or pass a reuse flag); campaign creation is NOT idempotent, unlike every step above it.
6. **Activate ("run") the campaign** — required before any journey can attach to it.
7. **Optionally share** the campaign with a partner org.
8. **Cache the resolved ids** (campaign id, template group id) in `customData` so subsequent runs
   skip straight to using them instead of re-running the lookup chain.

## Minimal example

```ts
import { ensureWorkflow } from "@/lib/api"

const res = await ensureWorkflow({
  templateName: "myapp",                     // finds or clones the catalog template
  campaignName: `MyApp – ${partnerName}`,
  reuseExistingCampaign: true,                // don't create a duplicate campaign
  onProgress: (p) => setStatus(p.message),    // finding → creating → activating → done
})

if (res.success) startJourney(res.campaignId!)
else showError(res.error)
```

`ensureWorkflow` runs the whole flow above. Unpacked, the pieces are `ensureTemplateGroup(name)`
(steps 1–4) plus `createCampaign` / `activateCampaign` / `findCampaignByName` (5–6) from
`campaign.ts`.

## Gotchas

- **Campaign creation is not idempotent** — always `findCampaignByName` first (or set
  `reuseExistingCampaign: true`), or every bootstrap run (e.g. every cold start) mints a new
  duplicate campaign.
- **A created campaign isn't usable until activated** — journeys can't attach to a campaign that
  hasn't been `run` yet.
- **The publish payload must be the cleaned shape, not the raw draft GET body** — extra fields
  from the rich draft response can fail the publish; always strip to the minimal node shape first.
- **`id`/`nodeId` must be coerced to strings** in the cleaned node payload even though the draft
  GET returns them as numbers.
- **A campaign hangs off TWO different templates** (the design-time group template you author, and
  a campaign-base CLONE that new journeys actually copy from) — provisioning gives you the group;
  see [workflows-journeys-steps.md](workflows-journeys-steps.md) for which one you need when.

## Related

- [workflows-journeys-steps.md](workflows-journeys-steps.md) — running journeys against the
  campaign you just provisioned.
- [stamp-config-onto-journey.md](stamp-config-onto-journey.md) — a template clone does not carry
  step-level notification/webhook config; you copy it separately after provisioning.
- [resolve-actionable-step.md](resolve-actionable-step.md) — resolving a specific step once you
  have a template id.
- Concepts: [setup/prototype-to-app.md](../setup/prototype-to-app.md), [api/README.md](../api/README.md).
