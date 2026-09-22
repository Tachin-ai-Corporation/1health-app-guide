# Mirror-pair bidirectional share

> **Advanced / guardrailed pattern.**

**Use when:** the platform's sharing primitive is one-way (an owner shares OUT to a partner), but
your product needs a bidirectional channel where each side can send the other something through
what looks like one shared space.
**Routes:** n/a — client-side aggregation over `POST /api/v3/health/grid/workflow-campaign`
(list your campaigns) → [agents.md](https://agents.1health.io/public/prod/api/v3/health/grid/workflow-campaign/agents.md)
plus the share endpoint from F1.
**Reference code:** [`dashboard.tsx`](https://github.com/Tachin-ai-Corporation/v0-1health-secure-share/blob/main/components/dashboard.tsx#L104) (`deduplicateMirrors`)
**Seen in:** secure-share (bidirectional file-drop channels)

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
function mirrorKey(name: string, partnerLabel: string): string {
  return `${name.toLowerCase()}::${partnerLabel.toLowerCase()}`
}

function dedupeMirrors(campaigns: Campaign[], myTenantId: number): DisplayChannel[] {
  const groups = new Map<string, Campaign[]>()
  for (const c of campaigns) {
    const key = mirrorKey(c.name, partnerLabelFor(c, myTenantId))
    groups.set(key, [...(groups.get(key) ?? []), c])
  }
  return [...groups.values()].map((group) => {
    const primary = group.sort((a, b) => +new Date(b.updated) - +new Date(a.updated))[0]
    return { ...primary, allCampaignIds: group.map((c) => c.id) }
  })
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
