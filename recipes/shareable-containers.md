# Shareable containers

> **Advanced / guardrailed pattern.**

**Use when:** your product's unit of sharing is a named, describable bundle of journeys/files (a
"container," "room," "channel") built on top of a campaign, rather than the campaign itself being
the user-facing concept.
**Routes:** `POST /api/v2/health/workflow-campaign` (create) →
[agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-campaign/agents.md) →
`.../run` (activate) → `.../share` (see F1) → `POST /api/v3/health/grid/workflow-campaign`
(list / duplicate check) → [agents.md](https://agents.1health.io/public/prod/api/v3/health/grid/workflow-campaign/agents.md)
**Reference code:** [`containers.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-secure-share/blob/main/lib/api/containers.ts#L111) ·
[`create-container-flow.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-secure-share/blob/main/lib/api/create-container-flow.ts#L41)
**Seen in:** secure-share

## Pattern

1. **Model the container as a campaign** whose name/description ARE its user-facing identity — a
   product concept layered on the campaign primitive, not new platform storage.
2. **Orchestrate creation as one guarded sequence with progress callbacks**: ensure the base
   template exists → create → activate → share — a multi-second setup shouldn't look hung.
3. **Guard against duplicates before creating** — check the grid view for an existing container
   with the same name AND partner rather than relying on the platform to reject one.
4. **Parse each "item" (a journey) from its whole nested step tree in one relationship query per
   page**, not one call per item — a journey with no uploaded file yet is still a real, displayable
   row (e.g. "unshared"), not one to drop from the list.

## Minimal example

```ts
async function createSharedContainer(
  name: string,
  partnerOrgId: number,
  partnerLabel: string,
  onProgress: (msg: string) => void,
): Promise<{ containerId: number }> {
  onProgress("Setting up template…")
  const workflowTemplateGroupId = (await ensureTemplateGroup(TEMPLATE_NAME)).data!

  onProgress("Creating container…")
  const created = await createCampaign({
    name,
    description: `Shared container with ${partnerLabel}`,
    workflowTemplateGroupId,
  })
  if (!created.success) throw new Error(created.error)

  onProgress("Activating…")
  await activateCampaign(created.data!.id)
  onProgress("Sharing…")
  await shareCampaignWithPartner(created.data!.id, partnerOrgId)
  return { containerId: created.data!.id }
}
```

## Gotchas

- **Your own duplicate-name check is best-effort, not a database constraint** — a race between two
  tabs can still create two containers with the same name.
- **Encoding an identity into a free-text field** (to make it filterable) is a workaround, not a
  queryable attribute — it breaks if the partner's display name changes.
- **A container is still just a campaign underneath** — every campaign-level gotcha (activate
  before use, share is one-way, no delete) applies here too.

## Related

- [share-with-partner-org.md](share-with-partner-org.md) (F1)
- [mirror-pair-bidirectional-share.md](mirror-pair-bidirectional-share.md) (F3, Advanced)
- [auto-mirror-on-first-write.md](auto-mirror-on-first-write.md) (F4, Advanced)
- [provision-templates-and-campaigns.md](provision-templates-and-campaigns.md) (D3) — the
  find/clone/publish sequence behind `ensureTemplateGroup`.
