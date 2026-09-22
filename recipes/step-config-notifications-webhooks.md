# Configure step-level notifications and webhooks

**Use when:** users need to be notified — by email or their own webhook — when a specific workflow
step completes (e.g. "email me when a file is dropped," "POST to my endpoint when this step is
done").
**Routes:** read via `POST /api/v2/query` (resolve template+step, see
[resolve-actionable-step.md](resolve-actionable-step.md)) then `GET .../workflow-template/{templateId}/step/{stepId}/configuration` → [route docs](https://agents.1health.io/public/prod/api/manifest.md) · write via `PUT .../workflow-template-step/{stepId}/configuration` → [route docs](https://agents.1health.io/public/prod/api/manifest.md)
**Reference code:** [`lib/api/step-config.ts`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/lib/api/step-config.ts) · [`lib/api/step-subscriptions.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-secure-share/blob/main/lib/api/step-subscriptions.ts)
**Seen in:** secure-share, template

## Pattern

1. **"Notification settings" are template config, not a separate settings store.** They live as
   `notifications` (email) and `webhooks` arrays on a STEP's configuration DTO, at whichever
   template layer you choose to edit — usually the campaign's base template, for "the default
   going forward" (see the four-layer model in
   [provision-templates-and-campaigns.md](provision-templates-and-campaigns.md)).
2. **Read first.** Resolve the template+step id you're targeting, then `GET` its `/configuration`
   — the response includes the current `notifications` and `webhooks` arrays in the exact shape
   the write endpoint expects back.
3. **Write one concern at a time.** The write is partial **at the top level only**: a body of
   `{ webhooks: [...] }` leaves `notifications` untouched and vice versa — so save the two
   concerns in separate `PUT`s.
4. **But each array itself is replaced wholesale.** Sending `notifications` (or `webhooks`) means
   THAT ENTIRE ARRAY is what the step ends up with — so round-trip every sibling row you're not
   touching (the existing row, minus `id`) alongside the one you're adding/editing, or it's
   silently deleted.
5. **Drop `id` from every row you send** (the server reuses/reassigns it) and **preserve unknown
   fields by spreading the existing row** rather than hand-building a fresh object — the backend
   validates required sibling scalars on write (notifications: `notifyPatient`, `notifyCustomer`,
   `sendCompletionLink`, `smsMessage`, `completionButtonLabel`; webhooks: `customBody`,
   `customBodyModel`, retry settings) that must be present even when you're not changing them.
6. **Set the trigger phase deliberately.** Use `whenToExecute: ["On Step Completion"]` for a "step
   is done" event — see the Gotcha below before reaching for `"On Step Submit"`.

## Minimal example

```ts
import { resolveCampaignSteps, fetchStepConfiguration } from "@/lib/api"
import { setStepNotificationEmails, setStepWebhook } from "@/lib/api"

// READ — resolve the target step, then its current config.
const s = await resolveCampaignSteps(campaignId)
const step = s.data!.childSteps.find((x) => x.name === "Document Upload")!
const cfg = await fetchStepConfiguration(s.data!.templateId, step.id)

// WRITE — one PUT per concern; the helper round-trips siblings and drops `id`.
await setStepNotificationEmails(step.id, cfg.data!.notifications ?? [], ["ops@acme.com"], {
  emailSubject: "New file", emailMessage: "A new file was dropped.",
})

await setStepWebhook(step.id, cfg.data!.webhooks ?? [], {
  endpointUrl: "https://example.com/hooks/1health",
  header: { "X-Api-Key": "…" },              // plain object, NOT an array
  failureNotificationEmails: ["alerts@acme.com"],
})   // pass null to remove (PUTs {webhooks:[]})
```

## Gotchas

- **PUT replaces the WHOLE array** — always round-trip siblings (existing rows minus `id`)
  alongside your change; omitting one deletes it.
- **"On Step Completion" vs. "On Step Submit" is a trap.** They're different trigger-phase
  strings. A row saved with the wrong one persists fine — recipients "look" saved in the UI — but
  never fires. When a step's single submit both saves and completes it (the common dynamic-fields
  case), you almost always want `"On Step Completion"`.
- **A webhook's `header` is a plain `{name: value}` OBJECT, not an array** — convert an editable
  name/value-pairs UI to/from this shape at the boundary.
- **Sending an explicit empty array clears that concern** (`{webhooks: []}` is the documented
  *removal* path) — omit the key entirely if you mean "leave this alone," don't send `[]`.
- **The write is step-scoped (no `templateId` in its URL) while the read is template+step-scoped**
  — the two endpoints aren't symmetric, don't assume one implies the other's shape.
- **Which layer's step you PUT decides the blast radius** — the campaign base's step config is the
  default for that campaign's future journeys; a single journey's own step config scopes to just
  that journey (see [provision-templates-and-campaigns.md](provision-templates-and-campaigns.md)).

## Related

- [resolve-actionable-step.md](resolve-actionable-step.md) — resolving the `templateId`/`stepId`
  you read and write here, robustly and cross-org.
- [stamp-config-onto-journey.md](stamp-config-onto-journey.md) — this config does NOT
  automatically carry onto a journey created from the template; you copy it separately.
- [provision-templates-and-campaigns.md](provision-templates-and-campaigns.md) — the template-layer
  model this configuration lives inside.
- [workflows-journeys-steps.md](workflows-journeys-steps.md) — the step lifecycle this
  configuration reacts to.
