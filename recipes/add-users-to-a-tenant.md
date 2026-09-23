# Add users to a tenant

**Use when:** an admin needs to bring people into a tenant — a bulk, self-service allowlist, or a
single contextual invite with a role assigned right now — and then move them through approve /
deny / deactivate / renew as their membership evolves.
**Routes:** `POST /api/v3/user-management/pre-approved` (not yet in the published docs) ·
`POST /api/v3/user-management/pre-approved/upload` (not yet in the published docs) ·
`POST /api/v2/user/invite?isPatientOf=false&inviteToPortal=true` → [agents.md](https://agents.1health.io/public/prod/api/v2/user/invite/agents.md) ·
`PUT /api/v3/user-management/user/{id}/status` (not yet in the published docs)

> **⚠ Not yet in 1health's published API docs:** `POST /api/v3/user-management/pre-approved`, `POST /api/v3/user-management/pre-approved/upload`, and `PUT /api/v3/user-management/user/{id}/status`. 1health supports them for third-party apps, but agents.1health.io has no page for them yet — the shapes shown here come from working apps. Test them against demo before you rely on them.

**Reference code:** [`lib/api/patient.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/api/patient.ts#L436) (the `user/invite` call shape — that app uses different flags for a different purpose) — no public example calls the pre-approval endpoints; see the Minimal example for that shape.
**Seen in:** 1health platform usage

## Pattern

1. Default to the **pre-approval allowlist** for anything bulk or self-service: pre-approve an
   email (+ role), the person self-registers later against a link you hand out once, within an
   expiry window you don't manage per-row.
2. For a batch, validate the CSV **client-side before uploading** — dedupe by lower-cased email,
   check email format, check the role name against the tenant's real role list, and send only the
   rows that pass. Recommended caps: confirm with the admin above ~1,000 rows; hard-cap the batch
   at ~5,000 rather than letting an unbounded file hang the parser.
3. Track the bulk job through the **import/export log grid**, not a per-item status call — the
   upload returns a task id, but nothing polls it; the grid's own refresh is what tells the admin
   the batch landed (and which rows, if any, the server itself rejected).
4. Reach for the **direct invite** only for a one-off, contextual add: you already know the
   person's name/email/role and want them created-or-attached immediately, with an invite sent
   right away. Resolve `roleId` from the tenant's own role list first (see
   [scoped-api-key-with-role.md](scoped-api-key-with-role.md)) — there's no assign-by-role-name
   shortcut on the invite call itself.
5. Move a pending row through its lifecycle with **one** status-transition call, not a
   per-action endpoint — approve, deny, deactivate, and renew are all the same `PUT .../status`
   with a different target value. Compute which targets are legal from the row's **current**
   status before you even show the button: the backend still enforces it, but an ungated client can
   fire a technically-successful call that does the wrong logical thing (e.g. "approve" fired on a
   row that should only ever be "renewed").

## Primary vs fallback

- **Primary — pre-approval allowlist** (`POST /api/v3/user-management/pre-approved`, or
  `/pre-approved/upload` for a CSV batch): the self-service path — hand out a link, let people
  register against it, review/approve as they land.
- **Fallback — direct invite** (`POST /api/v2/user/invite`): a one-off add where you already know
  the person's details and want them created-or-attached right now, with an invite sent
  immediately and a role assigned up front.

## Minimal example

```ts
import { authFetch, getOneHealthBaseUrl } from "@/lib/auth-client"

const MAX_BULK_ROWS = 5000
const CONFIRM_ABOVE_ROWS = 1000 // surface a confirmation in the UI above this count

interface PreApproveRow { email: string; role: string }

/** Client-side gate before ever uploading a CSV — the backend never sees a dropped row. */
function cleanRows(rows: PreApproveRow[], validRoleNames: Set<string>): PreApproveRow[] {
  const seen = new Set<string>()
  return rows
    .filter((r) => {
      const email = r.email.trim().toLowerCase()
      if (!email.includes("@") || seen.has(email) || !validRoleNames.has(r.role)) return false
      seen.add(email)
      return true
    })
    .slice(0, MAX_BULK_ROWS) // hard cap — warn separately once rows.length > CONFIRM_ABOVE_ROWS
}

// Single pre-approval (`POST .../pre-approved { email, role }`) is the same shape as one row here.
async function preApproveBulk(cleanedCsv: File) {
  const baseUrl = getOneHealthBaseUrl()
  const form = new FormData()
  form.append("file", cleanedCsv) // already filtered by cleanRows() — only passing rows go up
  const res = await authFetch(`${baseUrl}/api/v3/user-management/pre-approved/upload`, { method: "POST", body: form })
  if (!res.ok) throw new Error(`Bulk upload failed: ${res.status}`)
  // The response's task id is not polled anywhere — watch the import/export log grid instead.
}

async function inviteUserDirectly(roleId: number, person: { firstName: string; lastName: string; email: string; phoneNumber: string }) {
  const baseUrl = getOneHealthBaseUrl()
  const res = await authFetch(`${baseUrl}/api/v2/user/invite?isPatientOf=false&inviteToPortal=true`, {
    method: "POST",
    body: JSON.stringify({ ...person, roleId }),
  })
  if (!res.ok) throw new Error(`Could not invite ${person.email}: ${res.status}`)
  return res.json() as Promise<{ id: number; email: string }>
}

// Exact wire strings for `status` aren't in the published docs yet — confirm spelling against demo.
type MembershipStatus = "PendingApproval" | "PreApproved" | "Active" | "Denied" | "Inactive" | "Expired"

/** Legal next states are computed from the row's CURRENT status, never chosen freely. */
function legalTransitions(current: MembershipStatus, emailVerified: boolean): MembershipStatus[] {
  if (current === "PendingApproval") return ["Active", "Denied"]
  if ((current === "Denied" || current === "Expired") && emailVerified) return ["Active"]
  if ((current === "Denied" || current === "Expired") && !emailVerified) return ["PreApproved"] // renew
  if (current === "Active") return ["Inactive"]
  return []
}

async function setMembershipStatus(userId: number, status: MembershipStatus) {
  const baseUrl = getOneHealthBaseUrl()
  const res = await authFetch(`${baseUrl}/api/v3/user-management/user/${userId}/status`, {
    method: "PUT",
    body: JSON.stringify({ status }),
  })
  if (!res.ok) throw new Error(`Could not update status: ${res.status}`)
}
```

## Gotchas

- **The bulk upload's task id is never polled anywhere** — watch the import/export log grid for
  the job's outcome instead of waiting on the create call's response.
- **Only the rows that pass client-side validation are ever sent** — the backend never
  independently re-validates a dropped row, so your validation is the only gate; get it right
  before upload.
- **The same target status can mean different things depending on the row's starting state** —
  "Active" is an approve from a pending row but a re-approve from a denied one; gate the button by
  current status, not just the status you want to reach.
- **A row denied/expired without ever completing registration can only be renewed back to
  pre-approved**, not approved straight to active — whether the email was ever verified is the
  signal for which one applies.
- **`roleId` on the direct invite must come from the tenant's own role list** — there's no
  assign-by-name shortcut on this call.
- **These three routes aren't in the published docs yet** — confirm field names and status-string
  spelling against demo before shipping a UI around them.

## Related

- [scoped-api-key-with-role.md](scoped-api-key-with-role.md) — resolving a role id the same way.
- [verify-a-contact-channel.md](verify-a-contact-channel.md) — the mechanisms a self-registration
  link's own verification step relies on.
- [tenant-security-policy.md](tenant-security-policy.md) — the tenant-wide policy layer this sits
  alongside.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
