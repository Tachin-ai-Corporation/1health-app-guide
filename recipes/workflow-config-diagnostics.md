# Workflow config diagnostics

> **Advanced / guardrailed pattern.**

**Use when:** a step notification or webhook "isn't firing" and you need to see, at a glance,
exactly what's configured on the whole step tree for a campaign — a diagnostic dev tool, not a
production code path.
**Routes:** n/a — diagnostic helper over `POST /api/v2/query` (resolve the step tree) →
[agents.md](https://agents.1health.io/public/prod/api/v2/query/agents.md) + `GET /api/v2/health/workflow-template/{templateId}/step/{stepId}/configuration`
→ [route docs](https://agents.1health.io/public/prod/api/manifest.md)
**Reference code:** [`webhook-diagnostics.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-secure-share/blob/main/lib/api/webhook-diagnostics.ts#L178)
**Seen in:** secure-share (console-only debug tool, not wired into production UI)

## Pattern

1. **Resolve the campaign to its base template id and full step tree** (root + child steps) — the
   same relationship query the step-config foundation recipe uses.
2. **`GET` every step's `/configuration`** — root and each child — and read `webhooks` /
   `notifications` off the DTO.
3. **Log a structured table** — `{ stepId, name, role, webhooks, notifications }` — so you can see
   at a glance which exact step level holds the subscription that should be firing.
4. **Keep this out of any user-facing path.** One query plus N configuration `GET`s is fine on
   demand from an admin/debug action, wasteful as a page-load default.

## Minimal example

```ts
async function diagnoseCampaignSubscriptions(campaignId: number) {
  const { templateId, rootStep, childSteps } = (await resolveCampaignSteps(campaignId)).data!
  for (const step of [rootStep, ...childSteps].filter(Boolean)) {
    const config = await fetchStepConfiguration(templateId, step!.id)
    console.log(step!.name, {
      webhooks: config.data?.webhooks ?? [],
      notifications: config.data?.notifications ?? [],
    })
  }
}
```

## Gotchas

- **A subscription on the parent step does not fire when the CHILD step is what actually
  completes** on the triggering action — this tool exists to catch exactly that mismatch.
- **Don't wire this into a hot path** — fine on demand, wasteful on every render.
- **Treat the output as read-only diagnostic text** — use the step-config write recipe to actually
  change a subscription.

## Related

- [step-config-notifications-webhooks.md](step-config-notifications-webhooks.md) (D5) —
  reading/writing the config this tool dumps.
- [stamp-config-onto-journey.md](stamp-config-onto-journey.md) (D6) — why a journey's own step
  config can differ from its template's.
