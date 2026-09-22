# Stamp step config onto a newly created journey

**Use when:** you've configured notifications/webhooks on a campaign's base-template step (see
[step-config-notifications-webhooks.md](step-config-notifications-webhooks.md)), but journeys
created from that campaign never fire them — 1health does not clone a template step's
notification/webhook configuration onto the journeys made from it.
**Routes:** read via the pattern in
[step-config-notifications-webhooks.md](step-config-notifications-webhooks.md) (resolve base
template+step, then `GET .../configuration`) · write via the same
`PUT .../workflow-template-step/{stepId}/configuration` → [route docs](https://agents.1health.io/public/prod/api/manifest.md), targeted at the **journey's own** step id
**Reference code:** [`lib/api/step-subscriptions.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-secure-share/blob/main/lib/api/step-subscriptions.ts#L795) (`copyConfigToJourneyStep`) · [`lib/api/step-config.ts`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/lib/api/step-config.ts) (`updateStepConfiguration`, the generic partial-config writer)
**Seen in:** secure-share

## Pattern

1. **Know the gap.** A journey's step tree is a fresh clone of the campaign's base template, but
   1health does not copy that template step's `notifications`/`webhooks` onto the new journey's
   step — a brand-new journey's target step starts with EMPTY config even when the base template
   step has recipients or a webhook configured. This is a platform gap, not a one-time
   misconfiguration — every new journey needs the copy repeated.
2. **After creating the journey** (and before its target step completes), **read the SOURCE
   config** off the campaign's base-template step — [resolve](resolve-actionable-step.md) it, then
   `GET` its `/configuration`.
3. **Resolve the TARGET**: the same step on the journey you just created. It has its OWN step id —
   a different entity than the base template's step, even though it started as a clone of it.
4. **Strip `id` from every copied row** before writing — those ids belong to the base template's
   rows; the journey's step is a different `WorkflowTemplateStep` and the backend assigns its own.
5. **Normalize known footguns while you copy.** If the source has a notification whose
   `whenToExecute` is missing or still says `"On Step Submit"` (see the trap in
   [step-config-notifications-webhooks.md](step-config-notifications-webhooks.md)), correct it to
   `"On Step Completion"` on the way over — otherwise a long-standing base misconfiguration
   propagates to every new journey too.
6. **PUT the whole partial config onto the journey's step id**, fully awaited, BEFORE your own code
   submits/completes that step — the config must exist at the moment the completion event fires,
   not after.
7. **Make the copy best-effort.** Log loudly on failure (an unresolvable source, a failed read, a
   failed PUT) so a silently-not-firing webhook is diagnosable — but never fail the user's actual
   action (the upload / step submit) just because the config copy did.

## Minimal example

```ts
import { updateStepConfiguration } from "@/lib/api"

async function copyStepConfigToJourney(
  campaignId: number, journeyId: number, journeyStepId: number,
): Promise<{ success: boolean; error?: string }> {
  // 1. Read the source config off the campaign's base-template step.
  const source = await resolveBaseStepConfig(campaignId)   // see resolve-actionable-step.md
  if (!source || (source.notifications.length === 0 && source.webhooks.length === 0)) {
    return { success: true }                                // nothing configured -> nothing to copy
  }

  // 2. Strip ids (they belong to the base template's rows) + fix a known trigger-phase bug.
  const stripId = <T extends { id?: number }>({ id, ...rest }: T) => rest
  const fixPhase = (n: (typeof source.notifications)[number]) =>
    !n.whenToExecute?.length || n.whenToExecute.includes("On Step Submit")
      ? { ...stripId(n), whenToExecute: ["On Step Completion"] }
      : stripId(n)

  // 3. Stamp onto the JOURNEY's own step id, before it can complete.
  return updateStepConfiguration(journeyStepId, {
    ...(source.notifications.length && { notifications: source.notifications.map(fixPhase) }),
    ...(source.webhooks.length && { webhooks: source.webhooks.map(stripId) }),
  })
}

// Caller: create journey -> find target step -> copy config -> THEN submit/complete it.
await copyStepConfigToJourney(campaignId, journeyId, uploadStep.id)
await submitStepWithFile(journeyId, uploadStep.id, fields, fileFieldId, file)
```

## Gotchas

- **This is a platform gap, not a one-time fix** — there's no "fix it on the template and it
  propagates"; the copy must run for every journey.
- **Copy before the completing submit, fully awaited** — if the config PUT races (or follows) the
  completion event, the trigger has already fired-or-not before your config existed to catch it.
- **Strip `id` from every copied row** — reusing the base template's row ids against the journey's
  different step id will not behave like writing a fresh row.
- **Distinguish "base step has nothing configured" (fine, nothing to do) from "couldn't resolve or
  read the base step" (a real problem)** — collapsing them into one silent no-op hides the second
  case, which is exactly the one worth a loud warning.
- **Never let a config-copy failure block the user-visible action that triggered it** — this is a
  best-effort enhancement layered on top of a submit that must still succeed on its own.

## Related

- [step-config-notifications-webhooks.md](step-config-notifications-webhooks.md) — the read/write
  mechanics being copied here.
- [resolve-actionable-step.md](resolve-actionable-step.md) — resolving the source (base template)
  step whose config you're copying.
- [workflows-journeys-steps.md](workflows-journeys-steps.md) — where journey creation and step
  submission happen; this copy slots in between the two.
- [provision-templates-and-campaigns.md](provision-templates-and-campaigns.md) — the four-layer
  clone model this gap sits inside (clones copy the step TREE but not this config).
