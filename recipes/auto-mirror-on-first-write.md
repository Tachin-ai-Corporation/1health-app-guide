# Auto-mirror on first write

> **Advanced / guardrailed pattern.**

**Use when:** a user is looking at a partner's shared campaign (read-only — they don't own it) and
tries to write back (upload/send something) — you need to lazily create and share your own
reciprocal campaign at that moment, instead of a separate "set up sharing" step up front.
**Routes:** n/a — orchestrates provisioning (create → activate → share) triggered by a write
action; see share-with-partner-org.md and provision-templates-and-campaigns.md.
**Reference code:** [`container-detail.tsx`](https://github.com/Tachin-ai-Corporation/v0-1health-secure-share/blob/main/components/container-detail.tsx#L530) (`handleUploadFile`, "mirroring" branch)
**Seen in:** secure-share

## Pattern

1. **Before a write, check whether you already own a campaign in this mirror pair** — if so, write
   straight to it.
2. **If not, run the full provision-and-share flow inline**: find/clone the template, create,
   activate, and share the campaign with the same partner — show a distinct "setting up…" status.
3. **Fold the new campaign id into your in-memory mirror group immediately** so the rest of the UI
   picks it up without a full reload.
4. **Only then perform the normal write.** A failure during auto-mirror creation must abort the
   write with a clear error — never half-create a channel and also fail the upload silently.

## Minimal example

```ts
async function uploadToChannel(channel: DisplayChannel, file: File) {
  let myCampaignId = channel.myCampaignIds[0] ?? null

  if (!myCampaignId) {
    setStatus("mirroring")
    const created = await ensureWorkflow({
      templateName: TEMPLATE_NAME,
      campaignName: channel.name,
      share: { partnerOrgId: channel.partnerOrgId },
    })
    if (!created.success || !created.campaignId) {
      throw new Error(created.error ?? "Could not set up your side of this channel")
    }
    myCampaignId = created.campaignId
    channel.allCampaignIds.push(myCampaignId)
    channel.myCampaignIds.push(myCampaignId)
  }

  return uploadToCampaign(myCampaignId, file)   // normal journey-create + step-submit + upload
}
```

## Gotchas

- **This puts provisioning on the critical path of a user action** — slower the first time for
  every new partner; surface a distinct status so it reads as "setting up," not a hang.
- **Share the new campaign with the SAME partner** the read-only one came from — resolve the
  partner org id from the existing campaign, don't ask the user to pick it again.
- **Update your in-memory mirror-group state immediately** — otherwise the next write re-triggers
  auto-mirroring.

## Related

- [mirror-pair-bidirectional-share.md](mirror-pair-bidirectional-share.md) (F3, Advanced)
- [share-with-partner-org.md](share-with-partner-org.md) (F1)
- [provision-templates-and-campaigns.md](provision-templates-and-campaigns.md) (D3) — the
  find/clone/publish/create/activate sequence this runs inline.
