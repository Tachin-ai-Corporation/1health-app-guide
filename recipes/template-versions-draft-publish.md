# Manage a workflow template's draft, published, and historical versions

**Use when:** you're building tooling that authors or manages workflow templates directly — beyond
the one-time bootstrap in [provision-templates-and-campaigns.md](provision-templates-and-campaigns.md)
— and need to decide which version to read, move a historical version back into an editable draft,
or move a whole template group between tenants/environments.
**Routes:** `GET .../workflow-template-group/{id}` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-template-group/agents.md) · `GET .../workflow-template-group/list` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-template-group/list/agents.md) · `GET .../published/list` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-template-group/published/list/agents.md) · `POST .../{id}/clone` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-template-group/_id_/clone/agents.md) · `PUT .../{id}/template/{templateId}/clone` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-template-group/_id_/template/_templateId_/clone/agents.md) · `GET .../{id}/workflow-template/{workflowTemplateId}` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-template-group/_id_/workflow-template/agents.md) · `GET/PUT .../workflow-template/{id}` (`?setAsPublished=true`) → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-template/agents.md) · `POST .../workflow-template-group/import` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-template-group/import/agents.md) · `GET .../{id}/export` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-template-group/_id_/export/agents.md)
**Reference code:** [`lib/api/workflow-provisioning.ts`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/lib/api/workflow-provisioning.ts) (`getTemplateGroupDetail`, `getDraftTemplateConfig`, `publishDraftTemplate` — the draft/published read and clean-node publish this recipe extends with the fuller version model)
**Seen in:** template, secure-share, pcp-tcm (the group/draft/publish mechanics via
[provision-templates-and-campaigns.md](provision-templates-and-campaigns.md)); the version-history
and import/export model is 1health platform usage

## Pattern

1. **Model a group as three layers.** A template GROUP is the long-lived, named thing you author.
   It has exactly one `draft`, at most one `published` version, and a `previousVersions` list (all
   `{id, name}` pointers) — read the group detail to get all three at once.
2. **Only one version is ever "the draft."** You can't have two drafts in flight for one group. To
   edit a published or historical version, clone that specific version back into a fresh draft
   first (`PUT .../template/{templateId}/clone`, targeting the version's own id — returns the new
   draft's id) — you cannot `PUT` a non-draft version in place.
3. **Save-as-draft and publish are the same endpoint**, discriminated by the `setAsPublished` query
   flag on `PUT /workflow-template/{id}`. Saving (flag omitted or `false`) never validates —
   iterate freely. Publishing (`true`) runs structural validation (every branch connected, nothing
   orphaned) — only pay that cost when you mean to go live.
4. **The draft `GET` returns a rich node shape; the `PUT` wants a minimal one.** Strip each node
   recursively to `{ id, nodeId, availableStepId, name, type, metadata, node? }` (coercing
   `id`/`nodeId` to strings) before writing — extra fields from the rich read can fail the write.
   This applies to every save/publish call against this endpoint, not just a first-time bootstrap.
5. **Two reads answer two different questions.** The group-scoped published read
   (`GET .../workflow-template-group/{id}/workflow-template/{workflowTemplateId}`) is read-only and
   always "what's live for this group right now." The plain by-id read/write
   (`GET/PUT /workflow-template/{id}`) is whichever specific version you pass — editable only while
   it's the group's current draft.
6. **Move a whole group between tenants/environments with export/import**, instead of re-authoring
   a template by hand: `export` produces a file for a group; `import` (multipart) creates a new
   group from it. Treat the exported file as an opaque blob to store and re-upload, not something
   to parse or edit.

## Primary vs fallback

- **Primary — save as draft:** `PUT /workflow-template/{id}` with `setAsPublished` omitted or
  `false`. No structural validation runs — safe to call on every edit, even a half-finished graph.
- **Fallback — publish:** the same `PUT`, `?setAsPublished=true`. Switch to this only when the step
  tree must be complete and valid (every branch connected, nothing orphaned) — expect a rejection
  on an invalid graph, unlike the draft save.
- **Primary — the group-scoped published read:** use `GET .../workflow-template-group/{id}/workflow-template/{workflowTemplateId}`
  when you need "what's live for this group right now" and want the server to enforce read-only.
- **Fallback — the by-id draft read:** use `GET/PUT /workflow-template/{id}` when you're authoring
  the current draft, or reading any specific version (published or historical) you already hold the
  id for.

## Minimal example

```ts
import { authFetch, getOneHealthBaseUrl } from "@/lib/auth-client"

const baseUrl = getOneHealthBaseUrl()

// 1. Read the group: published / draft / history pointers, all in one call.
const group = await (await authFetch(`${baseUrl}/api/v2/health/workflow-template-group/${groupId}`)).json()
// group.published?.id · group.draft?.id · group.previousVersions?: { id, name }[]

// 2. Want to edit a historical (or the current published) version? Clone it into a fresh draft.
const cloneRes = await authFetch(
  `${baseUrl}/api/v2/health/workflow-template-group/${groupId}/template/${targetVersionId}/clone`,
  { method: "PUT" },
)
const newDraftId: number = await cloneRes.json()

// 3. Edit the draft freely — no structural validation runs on a plain save.
await authFetch(`${baseUrl}/api/v2/health/workflow-template/${newDraftId}`, {
  method: "PUT",
  body: JSON.stringify({ rootNodes: editedRootNodes, stickyNotes }),
})

// 4. Publish when the whole graph must be valid — same endpoint, one query flag, and the
//    cleaned/minimal node shape (see provision-templates-and-campaigns.md for the stripping helper).
await authFetch(`${baseUrl}/api/v2/health/workflow-template/${newDraftId}?setAsPublished=true`, {
  method: "PUT",
  body: JSON.stringify({ rootNodes: cleanedRootNodes, stickyNotes }),
})
```

## Gotchas

- **A published or historical version is read-only, enforced server-side** — a canvas UI may also
  block editing client-side, but that's on top of, not instead of, the server rejecting a `PUT`
  against a non-draft version's id. Clone to draft first, always.
- **The clean/minimal node shape trap applies to every write**, not just a provisioning bootstrap's
  first publish — a rich draft `GET` body sent back as-is can fail the `PUT`.
- **`id`/`nodeId` must be coerced to strings** in the node payload even though reads return them as
  numbers.
- **The exported file's format isn't specified** beyond "a file" — round-trip it as an opaque blob
  rather than trying to inspect or edit its contents.

## Related

- [provision-templates-and-campaigns.md](provision-templates-and-campaigns.md) — the one-time
  find-or-clone-or-publish bootstrap this recipe's version model sits underneath.
- [campaign-lifecycle-and-audience.md](campaign-lifecycle-and-audience.md) — re-pointing an active
  campaign at whatever version `use-latest-template` currently resolves to.
- [decision-steps.md](decision-steps.md) — authoring branch points inside a draft's step tree.
- [workflows-journeys-steps.md](workflows-journeys-steps.md) — the step tree shape a template
  version's `rootNodes` and a running journey's steps share.
