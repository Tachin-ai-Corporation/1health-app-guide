# Run any process as a workflow, with no patient

**Use when:** your process isn't about a patient (a file exchange, an export run, an approval, an
internal request) and you still want 1health's workflow engine for it: steps, status, files,
comments, assignment, sharing. The campaign vocabulary is patient-first, but a workflow doesn't
need a patient.
**Routes:** `POST /api/v2/health/workflow-campaign` (create) → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-campaign/agents.md) · `POST .../{id}/run` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/workflow-campaign/_id_/run/agents.md) · `POST /api/v2/journey` → [agents.md](https://agents.1health.io/public/prod/api/v2/journey/agents.md)
**Reference code:** [`create-container-flow.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-secure-share/blob/main/lib/api/create-container-flow.ts#L126) (a campaign per exchange channel, with no audience) · [`container-journeys.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-secure-share/blob/main/lib/api/container-journeys.ts#L44) (`createJourney(campaignId)`: a journey per file, no patient) · the template's [`lib/api/campaign.ts`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/lib/api/campaign.ts) (`createCampaign` already defaults to no audience)
**Seen in:** secure-share, a whole file-exchange product built on journeys that never involve a patient

## Pattern

1. **Treat the patient wording as describing enrollment, not a requirement.** The campaign types
   read "Labeled Patients" and "Cohort Patients". The docs describe a campaign as running a
   workflow "across a patient cohort". The create body carries `allowMultiplePatientJourneys`.
   All of that is about which patients a campaign enrolls when it runs. None of it is needed to
   run a process.
2. **Design the template with no assign-patient step.** Start it with whatever your process
   actually starts with. Secure-share's template goes: select the partner org → upload the file →
   download (or reject) it.
3. **Create the campaign with no audience:** `labelTagIds: []` and no cohort. It's just the home
   your journeys hang off. Secure-share makes one per exchange channel ("container"); an export
   tool would make one per app or per org. Name it for the process, not a cohort, and find it by
   name before creating it, because campaign creation isn't idempotent.
4. **Run it anyway.** Journeys can only attach to a campaign that has been run. With no audience,
   the run enrolls nobody, which is exactly what you want.
5. **Start a journey each time the process happens**, with `POST /api/v2/journey { campaignId }`
   and nothing else: no patient and no subject. You can seed and submit the first step inline
   (`submitSteps`). Secure-share starts one journey per file.
6. **Leave `allowMultiplePatientJourneys` off.** It limits journeys *per patient*, so journeys
   with no patient aren't affected. Secure-share keeps it `false` and still creates a journey for
   every file in the same campaign.

The journey records who started it (its creator person, which secure-share reads as the sender).
You get "who ran it" without casting anyone as a patient.

## Primary vs fallback

- **Primary: a patient-less journey** on a template with no assign-patient step, for processes
  about a thing (a file, an export, a request, an approval). Journey status, step history, files,
  comments, and assignment all work unchanged.
- **Add a patient step only when the process is about a patient**, such as an intake, a care
  episode, or an outreach program. Then audiences, patient counts, and `allowMultiplePatientJourneys`
  do their normal jobs.
- **Fallback: `customData` state**, only when the process can't be a workflow at all
  ([custom-data-as-state-machine.md](custom-data-as-state-machine.md)).

## Minimal example

```ts
import { ensureWorkflow, createJourney } from "@/lib/api"

// Once: find or create the process's campaign and run it. The template's createCampaign already
// defaults to no audience (labelTagIds: []) and allowMultiplePatientJourneys: false.
const wf = await ensureWorkflow({
  templateName: "myapp-export",        // a template with no assign-patient step
  campaignName: "MyApp exports",       // named for the process, not a patient cohort
  reuseExistingCampaign: true,         // campaign creation isn't idempotent
})
if (!wf.success) throw new Error(wf.error)

// Every time the process happens: one journey, no patient or subject.
const journey = await createJourney(wf.campaignId!)
```

## Gotchas

- **Don't invent a patient.** Making the acting admin or employee a journey's patient just to fill
  the slot is wrong. So is turning on `allowMultiplePatientJourneys` for a patient-less process:
  it changes nothing for journeys without a patient. The actor is already recorded as the
  journey's creator.
- **Patient-first naming is everywhere.** You'll see it in the campaign types, the create
  endpoint's description, and `tagged-instance-count` ("patient count"). Read it as "who gets
  enrolled", not "what a journey must contain".
- **Audience counts read zero here.** `tagged-instance-count` counts the audience, and a campaign
  with no audience has none. Count its journeys instead: the template's `listJourneys` with
  `filterBy: [{ key: "workflowCampaignId", value: campaignId, operator: "equals" }]`.
- **The campaign still has to be run.** Running a campaign with no audience is allowed and enrolls
  nobody. Skipping the run means journeys can't attach.

## Related

- [workflows-journeys-steps.md](workflows-journeys-steps.md): starting and advancing the journeys.
- [provision-templates-and-campaigns.md](provision-templates-and-campaigns.md): the find/clone/publish + create/run flow behind `ensureWorkflow`.
- [campaign-lifecycle-and-audience.md](campaign-lifecycle-and-audience.md): the audience mechanisms you're choosing not to use here.
- [shareable-containers.md](shareable-containers.md): secure-share's containers, a product built this way.
- [custom-data-as-state-machine.md](custom-data-as-state-machine.md): the fallback when a process can't be a workflow.
