# Update an org's identity fields and branding assets

**Use when:** you need to write an organization/tenant's identity fields (tax id, NPI, HIPAA flag,
subdomain, org "types") and/or its branding (light/dark logo, light/dark icon) — and want to know
why one PUT doesn't do both.
**Routes:** `PUT /api/v2/tenant` → [agents.md](https://agents.1health.io/public/prod/api/v2/tenant/agents.md) (identity fields) · `POST /api/v2/health/type/{typeKey}/{instanceId}/relation/{relKey}/file/upload` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/type/_typeKey_/_instanceId_/relation/_relKey_/file/upload/agents.md) (branding files — generic relation upload)
**Reference code:** [`journey-attachments.ts`](https://github.com/Tachin-ai-Corporation/v0-trc-care-coordinator/blob/main/lib/api/journey-attachments.ts) (same generic relation-upload call, against a different relation) — none public for the identity PUT or for a branding relation specifically; see the Minimal example.
**Seen in:** trc-care-coordinator (the underlying upload mechanic, via [attachments.md](attachments.md)); 1health platform usage (branding as four independent relation slots)

## Pattern

1. Treat identity and branding as **two separate writes on two different objects** — don't expect
   one PUT to cover both.
2. Identity fields (tax id, DUNS, NPI, the HIPAA-covered-entity flag, subdomain, org "types") live
   directly on the tenant/organization record — write them with `PUT /api/v2/tenant`, sending the
   record's `id` plus only the fields you're changing.
3. `hipaaCoveredEntity` and `types` gate each other: which other fields are even relevant (e.g. an
   NPI) depends on both — re-validate the whole form when either changes, not just the field the
   user touched.
4. `subdomain` becomes **immutable** once set to a non-default value — a real DNS/OAuth-client side
   effect fires the first time it's set, and there's no documented way back. Confirm with the user
   before writing it on an existing tenant.
5. Branding is **not** a set of URL fields on the tenant record. Each of the four slots (light logo,
   dark logo, light icon, dark icon) is its own file, attached via the generic typed-entity relation
   upload route against your tenant's configuration instance — one call per slot.
6. Resolve the configuration instance's type key and its logo/icon relation keys **at runtime** (see
   [schema-discovery.md](schema-discovery.md)) rather than hardcoding them. Treat the four slots as
   independent: clearing or replacing one never touches the other three, and "the org's logo" is
   ambiguous until you say which of the four you mean.

## Minimal example

```ts
import { callApi } from "@/lib/api"

// Identity fields live on the tenant record itself — send only what's changing, plus `id`.
async function updateOrgIdentity(tenantId: number, fields: {
  taxId?: string
  duns?: string
  organizationNpiId?: number
  hipaaCoveredEntity?: boolean
  subdomain?: string          // one-way on an existing tenant — confirm with the user first
  types?: string[]            // e.g. ["Health Provider", "Go To Market"]
}) {
  const res = await callApi("tenant/update-identity", "/api/v2/tenant", {
    method: "PUT",
    body: JSON.stringify({ id: tenantId, ...fields }),
  })
  if (!res.success) throw new Error(res.error)
}

// Branding is four independent file slots, not identity fields — upload each separately.
async function uploadBrandingAsset(
  configTypeKey: string,     // your tenant's config type — resolve via schema-discovery.md
  configInstanceId: number,  // that instance's id
  logoRelationKey: string,   // e.g. the "light logo" slot — resolve, don't hardcode
  file: File,
) {
  const url =
    `/api/v2/health/type/${configTypeKey}/${configInstanceId}/relation/${logoRelationKey}/file/upload` +
    `?fileName=${encodeURIComponent(file.name)}&isPublic=true` // branding assets are typically public
  const form = new FormData()
  form.append("file", file, file.name)
  const res = await callApi<{ id: number; name: string }>("tenant/upload-branding", url, {
    method: "POST",
    body: form,
  })
  if (!res.success) throw new Error(res.error)
  return res.data
}
```

## Gotchas

- Branding is **four independent relation slots** — light logo, dark logo, light icon, dark icon.
  Clearing or replacing one never touches the other three.
- `subdomain` is a one-way door once set to a non-default value on an existing tenant — treat it as
  provisioning, not editing.
- `hipaaCoveredEntity` and `types` interact: changing one can make a previously-required field (like
  NPI) irrelevant, or newly required — re-validate the whole form.
- A public read of these assets (e.g. by a not-yet-logged-in visitor) comes back through
  `publicUrlLogo`/`publicUrlDarkLogo`/`publicUrlTitleIcon`/... on `GET /api/v2/public/tenant/config`
  — see [org-and-tenant-profile-reads.md](org-and-tenant-profile-reads.md) — not by re-reading the
  relation you just uploaded to.
- `PUT /api/v2/tenant` is the tenant's general-purpose update endpoint, not a narrow "identity" PUT
  — send only the fields you're changing plus `id`, the same read-modify-write caution as any
  partial update.

## Related

- [attachments.md](attachments.md) — the generic relation-upload mechanic this reuses.
- [schema-discovery.md](schema-discovery.md) — resolving the config type's relation keys at runtime
  instead of hardcoding them.
- [org-and-tenant-profile-reads.md](org-and-tenant-profile-reads.md) — reading these fields back.
- [tenant-provisioning.md](tenant-provisioning.md) — setting most of this at creation time instead
  of after the fact.
