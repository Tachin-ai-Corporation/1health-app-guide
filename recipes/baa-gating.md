# BAA gating

**Use when:** your app handles PHI and must not let an organization proceed until it has accepted 1health's Business Associate Agreement — an entry gate checked at login/first load, with the accepted document available to view afterward.
**Routes:** `GET /api/v2/agreement/_type_` → [agents.md](https://agents.1health.io/public/prod/api/v2/agreement/_type_/agents.md) · `PUT /api/v2/agreement/_type_/accept` → [agents.md](https://agents.1health.io/public/prod/api/v2/agreement/_type_/accept/agents.md)
**Reference code:** [`lib/api/baa.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/api/baa.ts) · [`app/api/baa/stamped/route.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/app/api/baa/stamped/route.ts) · [`lib/baa-stamp.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/baa-stamp.ts)
**Seen in:** pcp-tcm, expertdx, patient-vault

## Pattern

1. Treat "has this org accepted the BAA" as a **gate** checked once per session (or on each protected route load): read the agreement **by its type name** (a fixed string like `"BAA Organization Standard"`) and check `state.accepted`.
2. Both the read and the accept run on the **signed-in user's own token** — the agreement endpoints are caller-scoped, so accepting establishes that org's acceptance, tied to the identity actually bound by it.
3. Accept by `PUT`-ing the agreement's own `id`, read back from the GET and never invented client-side, plus any classification flag the accept call also sets (e.g. `hipaaCoveredEntity=true`).
4. When the org needs to view/download the *accepted* document later, don't just relay the platform's raw file: re-read the acceptance server-side at request time and, optionally, stamp those facts onto the PDF — so the artifact always reflects the platform's current record, never a client-asserted claim.
5. Fail closed: any read error routes the user back to the gate, never past it. Showing the gate to an already-accepted org is a minor annoyance; skipping it on a failed read is a compliance gap.

## Minimal example

```ts
import { authFetch, getOneHealthBaseUrl } from "@/lib/auth-client"

const BAA_TYPE = "BAA Organization Standard"

interface BaaAgreement {
  id: number
  accepted: boolean
}

// GATE CHECK — read on the caller's own token.
async function fetchBaaAgreement(): Promise<BaaAgreement | null> {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/v2/agreement/${encodeURIComponent(BAA_TYPE)}`)
  if (!response.ok) return null // fail closed: caller shows the gate
  const raw = await response.json()
  const row = Array.isArray(raw) ? raw[0] : raw
  if (typeof row?.id !== "number") return null
  return { id: row.id, accepted: row.state?.accepted === true }
}

// ACCEPT — id comes from the read above, never invented client-side.
async function acceptBaa(agreementId: number): Promise<boolean> {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(
    `${baseUrl}/api/v2/agreement/${encodeURIComponent(BAA_TYPE)}/accept?hipaaCoveredEntity=true`,
    { method: "PUT", body: JSON.stringify({ ids: [agreementId] }) },
  )
  return response.ok
}
```

## Gotchas

- The agreement is looked up **by name** (a fixed type string), not a numeric id you can hardcode — get the id from the GET response.
- Read and accept are **caller-scoped** — calling either under a privileged service key answers/acts for the *service's own* acceptance state, not the org's. See [baa-status-split-identity.md](baa-status-split-identity.md) for when a privileged read of a different, coarser flag is legitimately needed.
- A read failure must route to the gate, not past it — never treat "couldn't confirm" as "must be fine."
- If you serve the accepted document back to the user, re-derive the acceptance facts (date, signatory) from the platform at request time rather than accepting them as parameters — a route that stamped caller-supplied facts would let anyone mint a PDF asserting a signature that never happened.
- The underlying file is resolved from the id embedded in the agreement's own response, with a public-URL fallback — don't hardcode a file id.

## Related

- [baa-status-split-identity.md](baa-status-split-identity.md) — the advanced variant where a privileged key reads a different flag first.
- [sanitizing-bff-proxy.md](sanitizing-bff-proxy.md) — the proxy-shaping half of this same domain in another app.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md).
