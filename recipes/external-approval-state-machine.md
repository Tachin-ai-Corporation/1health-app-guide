# Track a long external approval as a state machine in custom data

> **Advanced / guardrailed pattern.**

**Use when:** a third party runs a multi-day/week approval or vetting process on your behalf, and
1health customData is the only place you can durably track where a given record stands.
**Routes:** state lives in customData — read via `POST /api/v2/query`, write via
`POST /api/v2/data/custom-data/bulk`; see [read-write-custom-data.md](read-write-custom-data.md).
**Reference code:** [`lib/kno2/entrant-profile.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/kno2/entrant-profile.ts#L100)
**Seen in:** pcp-tcm

## Pattern

1. Enumerate the states as a small closed set (e.g. `derived → confirmed → submitted → approved`)
   and **derive** the current state from which fields are populated — don't also store a status
   string that can disagree with the data.
2. Keep a low-stakes, machine-derived proposal separate from a high-stakes, human-confirmed fact.
   A later automated refresh must never silently overwrite what a person already confirmed.
3. Validate the whole record, field by field, **before** the external submit — a bad submission to
   an external approval body can be a real, consequential event.
4. The moment the external system hands back its own tracking id, persist it before anything
   else — some vendors cannot easily recover it later. Do the read-modify-write fail-closed (see
   [write-safety-and-fail-closed.md](write-safety-and-fail-closed.md)): refuse to write on a failed
   read, so a transient error can't erase a real record id.

## Minimal example

```ts
type Status = "none" | "derived" | "confirmed" | "submitted" | "approved"

interface Registration {
  derived?: Record<string, unknown>
  confirmed?: Record<string, unknown>
  submission?: { recordId: string; approvedAt: string | null }
}

function statusOf(reg: Registration): Status {
  if (reg.submission?.approvedAt) return "approved"
  if (reg.submission) return "submitted"
  if (reg.confirmed) return "confirmed"
  if (reg.derived) return "derived"
  return "none"
}

async function recordSubmission(orgId: string, submission: NonNullable<Registration["submission"]>) {
  const current = await readCustomData("Organization", orgId) // fail-closed: throws, never guesses
  await mergeCustomData("Organization", orgId, appData(appId, { registration: { ...current, submission } }))
}
```

## Gotchas

- Derive status from the data present; a parallel status enum will eventually disagree with it.
- A derived guess and a human confirmation are different trust levels — never let a refresh of the
  former overwrite the latter.
- Prefer the native workflow engine first (see
  [custom-data-as-state-machine.md](custom-data-as-state-machine.md)) — reach for this only when
  the external process has no journey/step to hang off of.

## Related

- [custom-data-as-state-machine.md](custom-data-as-state-machine.md) · [write-safety-and-fail-closed.md](write-safety-and-fail-closed.md) · [fail-closed-dedup-ledger.md](fail-closed-dedup-ledger.md)
