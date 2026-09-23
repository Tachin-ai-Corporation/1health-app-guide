# Campaign dashboard aggregation

**Use when:** you need KPI counts for a campaign — journeys by status, and optionally by journey
tag — formatted, ordered, and labeled the same way the native 1health campaign page shows them,
not just a raw count dump.
**Routes:** `GET/PUT /api/v2/health/workflow-campaign/{id}` (display config, read and — see below —
write) → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-campaign/agents.md)
· `POST /api/v2/health/workflow-campaign/{id}/dashboard` (counts) →
[agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-campaign/_id_/dashboard/agents.md)
· `POST .../{id}/dashboard/refresh` (force-recompute) →
[agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-campaign/_id_/dashboard/refresh/agents.md)
**Reference code:** [`campaign.ts`](https://github.com/Tachin-ai-Corporation/v0-trc-care-coordinator/blob/main/lib/api/campaign.ts#L167) (`fetchCampaignDashboard`)
**Seen in:** trc-care-coordinator (coordinator KPI tiles)

## Pattern

1. **Start from the baseline call** if all you need is status counts: the dashboard endpoint alone
   returns a `total[]` array of `{ number, status }` — enough for a simple KPI row.
2. **When you also need journey-tag tiles** (e.g. a tile like "Cancelled – Data Received Late"
   backed by a label tag, matching what the platform's own campaign page shows), first `GET` the
   campaign detail and read `uiDetailsConfig.configs` — this is the authoritative, ordered display
   contract. Each entry is variant `"Total"` (a core status) or `"Journey Tag"` (carries a
   `labelTag: { id, name }`).
3. **Request only the tag ids the display config references** — collect the `labelTag.id`s from
   `"Journey Tag"` entries and send them as `journeyTags: [{ id }]` in the dashboard POST body.
4. **Index both response arrays defensively.** Core statuses come back as `total[]`; per-tag counts
   come back in a second array under a key that has been observed misspelled upstream — accept
   both the documented and the misspelled key. Normalize case before using a status/tag name as a
   lookup key.
5. **Re-assemble the stat list by walking `configs` in `order`**, resolving each entry's count from
   the indexed maps. This reproduces the exact tiles, labels, and order the platform's own
   dashboard would show for this campaign — including tiles a bare `total[]` read would never
   surface.
6. **Fall back to the raw arrays** (unordered, un-relabeled) if the display config isn't available
   for some reason — a plain count is still better than nothing.
7. **Force a recompute only when you suspect the counts are stale** — e.g. right after a bulk
   import or bulk tag change. `POST .../dashboard/refresh` takes no body and returns no dashboard
   data of its own; it's a signal to recompute, followed by a normal dashboard read. It's an
   optimization, not a precondition — the dashboard read still works without ever calling it.
8. **`uiDetailsConfig` is admin-writable, through the general campaign-edit `PUT`, not a
   tiles-specific endpoint.** Round-trip the WHOLE `uiDetailsConfig` blob you read back (the same
   read-modify-write discipline as any other partial update) — sending a partial config through
   this general-purpose PUT risks clobbering tiles you didn't mean to touch.

## Minimal example

```ts
import { authFetch, getOneHealthBaseUrl } from "@/lib/auth-client"

interface DashboardStat { number: number; status: string }

export async function fetchCampaignKpis(campaignId: number): Promise<DashboardStat[]> {
  const baseUrl = getOneHealthBaseUrl()

  // Step 1: the display contract — order, labels, and which tags to ask for.
  const detailsRes = await authFetch(`${baseUrl}/api/v2/health/workflow-campaign/${campaignId}`)
  const configs = detailsRes.ok ? ((await detailsRes.json())?.uiDetailsConfig?.configs ?? []) : []
  const journeyTags = configs
    .filter((c: any) => c.variant === "Journey Tag" && typeof c.labelTag?.id === "number")
    .map((c: any) => ({ id: c.labelTag.id }))

  // Step 2: the counts.
  const dashRes = await authFetch(`${baseUrl}/api/v2/health/workflow-campaign/${campaignId}/dashboard`, {
    method: "POST",
    body: JSON.stringify({ calendar: "week", journeyTags, steps: [] }),
  })
  const dash = await dashRes.json()
  const byStatus = new Map((dash.total ?? []).map((s: any) => [String(s.status).toLowerCase(), s.number]))
  const tagRows = dash.jouneyTags ?? dash.journeyTags ?? []   // upstream misspelling: accept both
  const byTagId = new Map(tagRows.map((t: any) => [t.id, t.number]))

  if (configs.length === 0) {
    return [...(dash.total ?? []), ...tagRows.map((t: any) => ({ number: t.number, status: t.name }))]
  }
  return configs
    .slice()
    .sort((a: any, b: any) => (a.order ?? 0) - (b.order ?? 0))
    .map((cfg: any) => ({
      status: cfg.configName,
      number:
        cfg.variant === "Journey Tag"
          ? byTagId.get(cfg.labelTag?.id) ?? 0
          : byStatus.get((cfg.status ?? cfg.configName).toLowerCase()) ?? 0,
    }))
}

// Call ONLY when counts are known/suspected stale (e.g. right after a bulk import) — it returns
// no data of its own, so always follow it with fetchCampaignKpis().
export async function refreshThenFetchCampaignKpis(campaignId: number): Promise<DashboardStat[]> {
  const baseUrl = getOneHealthBaseUrl()
  await authFetch(`${baseUrl}/api/v2/health/workflow-campaign/${campaignId}/dashboard/refresh`, { method: "POST" })
  return fetchCampaignKpis(campaignId)
}
```

## Gotchas

- **The journey-tag array's key has been observed misspelled upstream** (a transposed letter) —
  read both the documented spelling and the misspelling; don't assume either is stable across
  environments.
- **Tag names may arrive wrapped in literal escaped quotes** — strip them before display or before
  using the name as a lookup key.
- **`uiDetailsConfig.configs` is the source of truth for labels/order.** Don't hardcode your own
  KPI tile list — it will silently drift from what 1health's own UI shows for the same campaign.
- **Request only the tag ids you'll display.** Sending every label tag on the tenant needlessly
  widens the dashboard call for tiles you never render.
- **The plain baseline call is enough for status-only KPIs** — only add the details-config round
  trip when you need tag tiles too; it's a second network call.
- **Refreshing doesn't return the new counts** — it's a fire-and-then-re-read, not a
  refresh-and-return; always follow it with a normal dashboard read.
- **The tile-config `PUT` is the general campaign-edit endpoint** — it accepts (and will happily
  save) any other campaign field too, so build its body from a full read of the campaign, not a
  hand-built object containing only `uiDetailsConfig`.

## Related

- [env-pinned-campaign.md](env-pinned-campaign.md) (D12, Advanced) — once you know which campaign
  id to dashboard.
- [provision-templates-and-campaigns.md](provision-templates-and-campaigns.md) (D3) —
  creating/finding the campaign in the first place.
- [campaign-lifecycle-and-audience.md](campaign-lifecycle-and-audience.md) — the campaign's
  run/cancel/finish/restart lifecycle and its pre-flight population count, alongside these KPIs.
- [bulk-tagging.md](bulk-tagging.md) — applying the journey tags this recipe reads counts for.
