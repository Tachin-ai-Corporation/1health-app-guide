# The look-then-create idiom

**Use when:** you're about to create a record the platform treats as unique (a contact-point value,
an organization for a given identifier, a tenant by naming convention), and creating blind risks
either a duplicate-conflict 400 or — worse — a real duplicate record that silently succeeds.
**Routes:** n/a — a technique layered over whichever create endpoint you're using (e.g.
`POST /api/v2/organization/partner/{id}/contact-point`, `POST /api/v2/tenant`)
**Reference code:** [`lib/expertdx/registration.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/lib/expertdx/registration.ts#L433) (`findRegistrationContactPoint` / `createMobileContactPoint`) · [`lib/api/onboarding.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/api/onboarding.ts#L162) (`matchExistingVaultId`, `createTenant`)
**Seen in:** expertdx, pcp-tcm, patient-vault

## Pattern

1. **Look first**, using a read path that actually sees records created by anyone — not just "by
   me." Query direction can matter: traverse from the parent/owning record, not from the candidate
   record's own type, or a real duplicate can read back empty (see Gotchas).
2. If found, **reuse it** — return its id and a `reused: true` flag instead of creating anything.
3. If not found, **attempt the create.**
4. On a duplicate-conflict error from the create, **re-run the lookup once** (this covers a
   concurrent racer that created the record between your look and your create) before giving up.
   Only surface a hard conflict error if the second lookup also comes up empty.
5. **Variant — reuse by convention:** when there's no hard uniqueness constraint but you still want
   "one of these per app instance," match loosely by a stable marker substring (e.g. every tenant
   your app creates has a fixed word in its name) and converge deterministically — e.g. always the
   *lowest* matching id — so repeated bootstrapping runs never fork into near-duplicates.

## Minimal example

```ts
async function findThenCreateContactPoint(orgId: number, value: string) {
  const existingId = await findContactPointByValue(orgId, value) // traverse from the org, not the contact point
  if (existingId) return { id: existingId, reused: true }

  const created = await callApi<{ id?: number }>(
    "contact-point/create",
    `/api/v2/organization/partner/${orgId}/contact-point`,
    { method: "POST", body: JSON.stringify({ type: "Mobile", value }) },
  )
  if (created.success && created.data?.id) return { id: created.data.id, reused: false }

  // Duplicate-conflict: someone else may have just created it. Check once more before failing.
  const retryId = await findContactPointByValue(orgId, value)
  if (retryId) return { id: retryId, reused: true }

  throw new Error(`Could not create or find the contact point: ${created.error}`)
}
```

## Gotchas

- **Query direction can hide records you don't own.** Asking "from" the candidate record's own type
  can return nothing for a record created by someone/something else, even though it exists and
  blocks your create — traverse from the parent instead.
- **A uniqueness constraint may be scoped narrower than you assume** (e.g. unique per-parent, not
  platform-wide) — confirm the scope before treating a duplicate error as proof the record exists
  globally.
- **Prefer a true upsert when the create endpoint offers one** (it accepts an existing id to link):
  that's simpler and safer than racing create-then-catch.
- **For "reuse by convention," keep the match rule broad and the tie-break deterministic** — a narrow
  or non-deterministic match is exactly what lets repeated runs fork into duplicates instead of
  converging.

## Related

- [self-service-org-onboarding-by-npi.md](self-service-org-onboarding-by-npi.md), [tenant-provisioning.md](tenant-provisioning.md)
- [closed-vocabulary-writes.md](closed-vocabulary-writes.md) — a different retry-after-400 shape (strip-and-retry, not look-then-create).
- [write-safety-and-fail-closed.md](write-safety-and-fail-closed.md) — what to do when the "look" step itself can't be trusted.
