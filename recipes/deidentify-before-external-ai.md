# De-identify before an external AI call

**Use when:** you're about to send clinical data that originated in 1health to a third-party
AI/ML service (an LLM, a diagnostic model) that must not receive direct patient identifiers — even
though the case in 1health legitimately holds full identity.
**Routes:** n/a — this is a data-shaping gate you run *before* calling any external AI service; it
makes no 1health call itself and holds no credential.
**Reference code:** [`lib/expertdx/deident.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/lib/expertdx/deident.ts)
**Seen in:** expertdx

## Pattern

1. **Build the outbound payload by projection, not redaction:** explicitly name every field that's
   safe to send, and construct the payload only from that allow-list. A deny-list has to anticipate
   every way an identifier could show up (including in a field whose name suggests it's harmless,
   like a provenance quote); an allow-list only has to be right about what it includes, and
   silently drops anything new the source adds until you deliberately let it through.
2. **Re-express timing as relative, not absolute.** Pick an anchor date (e.g., the earliest event in
   the case), and send every other date as an offset from it (a day count, a "days before
   presentation" label) instead of a calendar date — the sequence of events is usually all the
   destination needs, and a relative number isn't an identifier.
3. **Scrub free text separately from structured fields.** Anything a human typed (a note, a
   referring question) can contain a name or a date in prose that structured projection can't
   catch — run it through a text-scrubber (strip this case's known identifiers, redact date-shaped
   substrings, band any age over the de-identification threshold) before it joins the payload.
4. **Gate the *assembled* payload with a function that throws**, and run it unconditionally right
   before the network call — never as an optional check. Verify two independent things at two
   different scopes: (a) the case's actual identifiers (name/DOB/MRN) don't appear anywhere in the
   serialized payload, and (b) no absolute-date-shaped or over-threshold-age substring survives in
   the free-text portions specifically (checking free text only avoids false positives from, e.g.,
   a numeric lab reference range like "11.0–13.5" matching a date pattern).
5. **Treat a caught violation as a hard stop, not a warning.** A gate failure means "this would have
   sent PHI to a third party" — fail the whole submission loudly rather than sending a
   partially-scrubbed payload or silently dropping the offending field.

## Minimal example

```ts
// Pure data-shaping — no network call, no credential. Runs just before the
// external call, which lives in its own server-only module.

export class DeidentificationError extends Error {}

interface CaseInput {
  caseId: string
  patientName: string; dob: string; mrn?: string
  labs: Array<{ analyte: string; value: string; collectedOn?: string; note?: string }>
  referringQuestion?: string
}

function identifierNeedles(input: CaseInput): string[] {
  const needles = input.patientName.split(/\s+/).filter((p) => p.length > 2)
  if (input.mrn) needles.push(input.mrn)
  needles.push(input.dob)
  return needles
}

function scrub(text: string, needles: string[]): string {
  let out = text
  for (const n of needles) out = out.replaceAll(n, "[patient identifier removed]")
  return out // a real implementation also redacts absolute dates and bands ages — see deident.ts
}

// Projection: name only the fields that are safe, never copy-then-remove.
export function buildDeidentifiedPayload(input: CaseInput, anchor: Date) {
  const needles = identifierNeedles(input)
  return {
    case_id: input.caseId, // a reference, never an identifier
    labs: input.labs.map((l) => ({
      analyte: l.analyte,
      value: l.value,
      day_offset: l.collectedOn ? daysBetween(anchor, new Date(l.collectedOn)) : undefined,
      note: l.note ? scrub(l.note, needles) : undefined,
    })),
    free_text: input.referringQuestion ? scrub(input.referringQuestion, needles) : undefined,
  }
}

function daysBetween(a: Date, b: Date) {
  return Math.round((b.getTime() - a.getTime()) / 86_400_000)
}

// The gate. Throws — never returns "probably fine."
export function assertDeidentified(payload: unknown, input: CaseInput): void {
  const haystack = JSON.stringify(payload).toLowerCase()
  for (const needle of identifierNeedles(input)) {
    if (haystack.includes(needle.toLowerCase())) {
      throw new DeidentificationError("Refusing to send: a patient identifier survived de-identification")
    }
  }
  // ...plus an absolute-date / over-threshold-age scan over the free-text fields only.
}

export function buildSafePayload(input: CaseInput, anchor: Date) {
  const payload = buildDeidentifiedPayload(input, anchor)
  assertDeidentified(payload, input) // never skip this — see Gotchas
  return payload
}
```

## Gotchas

- **Projection beats redaction:** build the payload by listing what's safe, not by copying the
  source and deleting what isn't — a deny-list silently ships the next field the source adds.
- **A field whose *name* sounds like metadata** (a "verbatim quote," a "provenance note") can still
  contain a full identifier string lifted off a source document — only allow-list it after checking
  what's actually in it, not because of what it's called.
- **Run the date/age scan only over free-text fields**, not the whole payload — a numeric range
  like "11.0–13.5" matches a naive date pattern and would make the gate reject every real case.
- **An age above a jurisdiction's de-identification threshold is itself an identifier** (e.g., 90
  under HIPAA Safe Harbor) — band it into a single open-ended category rather than sending the
  exact number, and confirm the destination's field actually accepts a banded/categorical value (an
  integer-only field may reject a string like "90+").
- **The gate must run unconditionally, immediately before the network call**, in the same process
  that makes the call — a check a new call site can forget to invoke isn't a gate.

## Related

- [external-job-pipeline.md](external-job-pipeline.md) — typically the very next step, submitting
  the now-safe payload.
- [deferred-record-creation.md](deferred-record-creation.md) — where the identifiers this gate
  protects usually come from.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
