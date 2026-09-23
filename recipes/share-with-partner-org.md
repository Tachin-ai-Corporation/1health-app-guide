# Share with a partner organization

**Use when:** you need to grant a partner organization access to something you own — most
commonly a whole campaign, so every journey under it becomes visible to the partner — without
making them a member of your tenant.
**Routes:** `POST /api/v2/health/workflow-campaign/{id}/share` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-campaign/_id_/share/agents.md) · `POST .../{id}/unshare` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-campaign/_id_/unshare/agents.md) · a single instance follows an analogous shape via `POST /api/v2/share` (not yet in the published docs)
**Reference code:** [`containers.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-secure-share/blob/main/lib/api/containers.ts#L178) (`shareContainer`)
**Seen in:** secure-share, trc-care-coordinator (via the template baseline)

> **⚠ Not yet in 1health's published API docs:** `POST /api/v2/share`. 1health supports it for
> third-party apps, but agents.1health.io has no page for it yet — verify its exact body shape
> against demo before you rely on it rather than assuming it mirrors the campaign-share body below.

## Pattern

1. **Resolve the partner organization's numeric id first** (see partner-org-typeahead.md) —
   sharing targets an organization `id`, not a display name or a tenant id.
2. **Share is one-directional.** You decide who can read/act on your campaign; the grant doesn't
   let the partner share it onward, and it doesn't give you anything back on their side.
3. **The body is an array of grants**, even for a single target —
   `[{ targetAccessEntity: "Partner Organization", targetEntityId, shareAccess }]` — so several
   targets or access levels can be granted in one call.
4. **`shareAccess` is a closed, graded enum — `"Read"` or `"Write"`, not a bare on/off.** Pick the
   least access the partner actually needs; `"Read"` is the common case, and `"Write"` is a real,
   distinct grant level — don't default every partner share to it just because it's the first value
   you saw in an example.
5. **Share after the campaign is activated.** Sharing an unactivated campaign doesn't fail loudly
   everywhere, but the partner sees nothing usable until journeys can actually run on it.
6. **Re-sharing the same target/access is harmless but not deduplicated.** If you want to avoid
   duplicate grant rows, check the campaign's existing shared-partner list before calling share
   again.
7. **Unshare is a real, explicit revoke — not a re-share with an empty array.** It targets the same
   shape minus the access level (`[{ targetAccessEntity: "Partner Organization", targetEntityId }]`)
   and is call-and-forget the same way share is — there's no "pending" state to poll.

## Minimal example

```ts
import { shareCampaignWithPartner, unshareCampaignWithPartner, fetchCampaign } from "@/lib/api"

// Grant a partner organization read access to everything under this campaign.
const result = await shareCampaignWithPartner(campaignId, partnerOrgId, "Read")
if (!result.success) throw new Error(result.error)

// Check who already has access before re-sharing.
const campaign = await fetchCampaign(campaignId)
const alreadyShared = campaign.data?.sharedPartnerOrganizations?.some((p) => p.id === partnerOrgId)

// Revoke it later — a real unshare, not a re-share with an empty grant list.
await unshareCampaignWithPartner(campaignId, partnerOrgId)
```

For a raw multi-target grant, build the array yourself:

```ts
import { shareCampaign } from "@/lib/api"

await shareCampaign(campaignId, [
  { targetAccessEntity: "Partner Organization", targetEntityId: partnerOrgId, shareAccess: "Read" },
])
```

## Gotchas

- **The grant body is an array even for one target** — a bare object is either silently wrong or
  rejected, depending on the endpoint.
- **`targetEntityId` is the partner ORGANIZATION id**, not its tenant id and not a
  partnership-record id — resolve the right one (see partner-org-typeahead.md's
  `PartnerOrganization.id`).
- **Sharing doesn't create a relationship either side can jointly manage.** From the partner's
  side, the campaign simply appears in their list. If you need each side to be able to send data
  back through what looks like one shared channel, see mirror-pair-bidirectional-share.md.
- **`sharedPartnerOrganizations` only reflects sharing done through this endpoint** — a partner who
  reached your data another way (e.g. a privileged cross-tenant read) won't show up here.
- **A single-instance (non-campaign) share isn't in the published docs** — see the banner above;
  confirm its exact request shape against demo rather than assuming it mirrors the campaign-share
  body.
- **Unshare, not another share call, is how you revoke** — sending an empty grants array to share
  is not the removal path; use the dedicated unshare endpoint instead.

## Related

- [partner-org-typeahead.md](partner-org-typeahead.md) (F2) — resolving the partner org id you
  share with.
- [mirror-pair-bidirectional-share.md](mirror-pair-bidirectional-share.md) (F3, Advanced) —
  presenting this one-way primitive as bidirectional.
- [shareable-containers.md](shareable-containers.md) (F5, Advanced) — building a product concept
  on top of a shared campaign.
- [provision-templates-and-campaigns.md](provision-templates-and-campaigns.md) (D3) — creating and
  activating the campaign before you share it.
