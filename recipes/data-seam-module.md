# Data seam module

**Use when:** a screen or workflow reasons about many fields whose real source will change over time (a manual entry today, an automated feed tomorrow) and you want the UI to never know or care which.
**Routes:** n/a — an organizing convention over calls you already make (`POST /api/v2/query`, the custom-data endpoints); not a route of its own.
**Reference code:** [`lib/toc/seams.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/toc/seams.ts)
**Seen in:** pcp-tcm

## Pattern

1. Pick one module as the single place a given screen/workflow reads and writes its data — every field the UI shows comes **through** it, never from an ad hoc call scattered across components.
2. For each field, document its **current source** (a real schema attribute, a `customData` key, a tenant-config value, a manual entry) and its **future source** (the automated feed or integration expected to replace it later) — even when the future source doesn't exist yet. This turns "we'll wire up the real feed later" into a one-function change instead of a UI rewrite.
3. Aggregate the independent reads in parallel (`Promise.all`) and degrade **per field**, not per screen — a seam module should never let one slow or failing sub-fetch blank the whole workflow; a missing piece renders as empty/unknown, not as a thrown error.
4. Namespace anything the seam itself persists under your app's own key (`appData.<appId>.<subKey>`) so it composes with whatever else already lives on that instance's `customData`.
5. Expose one load function and a small number of narrow patch/save functions from the module — callers pass a partial update, the seam merges and persists it; callers never construct the write payload themselves.
6. When a value can arrive from the platform in more than one shape (a bare id, or an object wrapping the id), coerce it to the shape the UI needs at the seam boundary — not at every call site that reads it.

## Minimal example

```ts
// lib/seams/workflow-seam.ts — the ONE place this workflow reads/writes its data.
//
// field            | current source                          | future source
// -----------------|------------------------------------------|---------------------------
// anchorDate       | Journey.created                          | upstream event-feed date
// contactPhone     | Person contact-point attribute            | unchanged
// complianceRecord | Journey customData (clinician-entered)    | unchanged
// orgDefaults      | Organization customData (appData)         | unchanged

import { readCustomData, appendCustomData } from "@/lib/api"
import { getContactPhone } from "@/lib/api/person"

export interface SeamData {
  journeyId: number
  anchorDate?: string
  contactPhone?: string
  complianceRecord: ComplianceRecord
  orgDefaults: Record<string, unknown>
}

export async function loadSeamData(journeyId: number, personId: number, orgId: number, appId: string): Promise<SeamData> {
  const [journeyData, contactPhone, orgData] = await Promise.all([
    readCustomData("WorkflowTemplate", journeyId),          // a journey instance, queried by its type key
    getContactPhone(personId).catch(() => undefined),        // one failed sub-fetch blanks THIS field only
    readCustomData("Organization", orgId).catch(() => ({})),
  ])
  return {
    journeyId,
    anchorDate: journeyData.anchorDate as string | undefined,       // CURRENT: journey field. FUTURE: event feed.
    contactPhone,
    complianceRecord: (journeyData.complianceRecord as ComplianceRecord) ?? emptyComplianceRecord(),
    orgDefaults: ((orgData.appData as any)?.[appId]?.workflowDefaults) ?? {},
  }
}

export async function patchComplianceRecord(journeyId: number, current: ComplianceRecord, patch: Partial<ComplianceRecord>) {
  const next = { ...current, ...patch, updatedAt: new Date().toISOString() }
  await appendCustomData(journeyId, { complianceRecord: next })     // flat top-level key: APPEND is safe here
  return next
}
```

## Gotchas

- **Document the future source even when nothing implements it yet** — an undocumented "we'll fix this later" field is indistinguishable from a permanent one, and the next person to touch the module has no way to know which fields are load-bearing placeholders.
- **Coerce platform object-or-scalar fields at the seam, once** — an id that sometimes arrives as a bare value and sometimes as `{ id, ... }` will otherwise crash a render deep in a component that has no context to debug it.
- **Degrade per field, not per screen** — one failed sub-fetch (a phone lookup, an optional integration) should blank that field, not throw and blank the whole workflow.
- **A seam is not a cache** — it re-reads on load. If you need to avoid re-hitting an expensive or rate-limited external call, cache that value *into* `customData` explicitly (see cache-reference-data-in-custom-data.md); don't quietly hold it in module state.

## Related

- [read-write-custom-data.md](read-write-custom-data.md)
- [per-user-preferences.md](per-user-preferences.md)
- [fail-closed-dedup-ledger.md](fail-closed-dedup-ledger.md)
- [multi-alias-payload-parsing.md](multi-alias-payload-parsing.md)
