# Mirror-pair bidirectional share

> **Advanced / guardrailed pattern.**

**Use when:** the platform's sharing primitive is one-way (an owner shares OUT to a partner), but
your product needs a bidirectional channel where each side can send the other something through
what looks like one shared space.
**Routes:** n/a — client-side aggregation over `POST /api/v3/health/grid/workflow-campaign`
(list your campaigns) → [agents.md](https://agents.1health.io/public/prod/api/v3/health/grid/workflow-campaign/agents.md)
plus the share endpoint from F1.
**Reference code:** none public — see the Minimal example.
**Seen in:** A secure file-sharing app (bidirectional file-drop channels)

## Pattern

1. **Each participant creates and shares their OWN one-way campaign** with the other — one logical
   "channel" is really TWO campaigns, one owned by each side.
2. **Define a mirror-pair key both sides land on independently** — e.g. `name + partner-identity`,
   lower-cased — without coordinating a shared id up front.
3. **Group your visible campaigns (yours + shared-to-you) by that key** and collapse each group to
   one display row: pick the most-recently-updated as primary, merge any stats you show.
4. **Fan reads out across every campaign id in the group** — a read against only the primary id
   silently drops the partner's half.
5. **Writes go to the campaign YOU own in the pair, never the partner's** — see
   auto-mirror-on-first-write.md for when your side doesn't exist yet.

## Minimal example

```ts
import type { Campaign } from "@/lib/api"

// Your helper: the org on the other side of a campaign (its owner, or whoever you shared it with).
declare function partnerOf(campaign: Campaign, viewerTenantId: number): { label: string; orgId: number }

/** One display row = every side of one mirror pair. */
interface DisplayChannel {
  shown: Campaign               // most recently updated side: the row's name and dates
  partner: { label: string; orgId: number }
  pairCampaignIds: number[]     // every side: fan reads out across all of these
  ownCampaignId: number | null  // your side, the only one you write to (null = not created yet)
}

const pairKey = (name: string, partnerLabel: string) =>
  [name, partnerLabel].map((part) => part.toLowerCase()).join("::")

const updatedMs = (campaign: Campaign) => Date.parse(campaign.updated ?? "") || 0

function collapseMirrorPairs(campaigns: Campaign[], viewerTenantId: number): DisplayChannel[] {
  const byPair = new Map<string, DisplayChannel>()
  for (const campaign of campaigns) {
    const partner = partnerOf(campaign, viewerTenantId)
    const key = pairKey(campaign.name, partner.label)
    const channel: DisplayChannel =
      byPair.get(key) ?? { shown: campaign, partner, pairCampaignIds: [], ownCampaignId: null }
    byPair.set(key, channel)

    channel.pairCampaignIds.push(campaign.id)
    if (updatedMs(campaign) > updatedMs(channel.shown)) channel.shown = campaign
    if (campaign.ownerOrganization?.tenantId === viewerTenantId) channel.ownCampaignId ??= campaign.id
  }
  return [...byPair.values()]
}
```

## Gotchas

- **The dedup key is an app-level naming convention, not a platform guarantee** — renaming one
  side's campaign silently breaks the pairing.
- **This is a UI-layer illusion.** The platform has no bidirectional-share concept — don't let it
  leak into permissions reasoning; each side still only controls its own one-way grant.

## Related

- [share-with-partner-org.md](share-with-partner-org.md) (F1) — the one-way primitive being
  paired up.
- [auto-mirror-on-first-write.md](auto-mirror-on-first-write.md) (F4, Advanced) — creating your
  side of the pair lazily.
- [shareable-containers.md](shareable-containers.md) (F5, Advanced) — the container concept each
  side of the pair is built from.
