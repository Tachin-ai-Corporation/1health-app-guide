# Env-pinned single campaign

> **Advanced / guardrailed pattern.**

**Use when:** your deployment serves exactly ONE fixed purpose per environment (e.g. one measure
dashboard per environment) and you'd rather pin the campaign id per environment than run
template/campaign discovery at runtime.
**Routes:** n/a — reads an environment variable chosen by the already-resolved auth environment;
no 1health call.
**Reference code:** [`page.tsx`](https://github.com/Tachin-ai-Corporation/v0-1health-med-adherence-bcbsm/blob/main/app/page.tsx#L6) (`getCampaignId`)
**Seen in:** med-adherence (one BCBSM measure campaign per environment)

## Pattern

1. **Resolve the environment the same way auth already resolved it** (e.g. a cookie set at
   token-exchange time) — don't introduce a second, uncrosschecked source of "which environment."
2. **Look up a per-environment env var** (`CAMPAIGN_ID_PROD`, `CAMPAIGN_ID_DEMO`, …) — never a
   single shared id, and never a cross-environment fallback.
3. **Treat a missing or unparseable id as a hard stop** (redirect / blank state) — never guess.
4. **Skip discovery entirely** — no template lookup, no listing, no provisioning; there is exactly
   one campaign this deployment will ever use, chosen at deploy time.

## Minimal example

```ts
function getCampaignId(environment: string | undefined): number | null {
  const raw =
    environment === "prod" ? process.env.CAMPAIGN_ID_PROD :
    environment === "demo" ? process.env.CAMPAIGN_ID_DEMO :
    null
  if (!raw) return null
  const id = Number.parseInt(raw, 10)
  return Number.isNaN(id) ? null : id
}
```

## Gotchas

- **This trades away multi-campaign discovery.** The moment the app needs a second campaign — a
  new period, a second product line, a per-partner campaign — this doesn't extend; you're back to
  name-based lookup or a customData-cached id list. Choose it only when "exactly one campaign,
  forever, per environment" is a real constraint, not a shortcut under deadline.
- **A missing env var must fail loudly**, never fall back to another environment's id — that
  silently mixes prod and demo data.
- **A recreated campaign requires a deploy** (an env var change), not a data fix — there is no
  runtime discovery to pick up a new id.

## Related

- [provision-templates-and-campaigns.md](provision-templates-and-campaigns.md) (D3) — the
  discovery-based alternative.
- [campaign-dashboard-aggregation.md](campaign-dashboard-aggregation.md) (D9) — what you do once
  you have the id.
