# Saved grid views

**Use when:** you want users to save, name, and reapply their own column layout, filters, and sort for a data grid — personal views — instead of hardcoding one fixed table shape.
**Routes:** `GET/POST /api/v2/grid-config` → [agents.md](https://agents.1health.io/public/prod/api/v2/grid-config/agents.md) · `PUT/DELETE /api/v2/grid-config/_viewId_` → [agents.md](https://agents.1health.io/public/prod/api/v2/grid-config/agents.md) (collection and item ops share the same doc page)
**Reference code:** [`lib/api/grid-config.ts`](https://github.com/Tachin-ai-Corporation/v0-trc-care-coordinator/blob/main/lib/api/grid-config.ts) · [`lib/api/mappers/grid-columns.ts`](https://github.com/Tachin-ai-Corporation/v0-trc-care-coordinator/blob/main/lib/api/mappers/grid-columns.ts) · [`use-saved-views.ts`](https://github.com/Tachin-ai-Corporation/v0-trc-care-coordinator/blob/main/components/data-grid/hooks/use-saved-views.ts)
**Seen in:** trc-care-coordinator · 1health platform usage (global/shared views)

## Pattern

1. Store each saved view as its own record: a `gridIdentifier` (which grid this view belongs to), a `name`, and an opaque `configuration` blob (JSON-stringified) — column order/width/visibility, filter model, sort state.
2. Keep exactly **one** bidirectional mapping table between your UI's column ids and the platform's field names, used both when building `configuration` for a save and when applying it back — don't translate ad hoc at each call site.
3. List/search saved views by `gridIdentifier` (+ optional name search) with normal pagination; treat a **404** as "no views yet," not an error.
4. Persist only a **pointer** — the last-applied view's id — client-side (e.g. `localStorage`), and use it to restore the actual configuration from 1health on load. The view data itself is never local-only.
5. Detect near-duplicate configurations before saving a new view by comparing **visible** columns only, so trivial differences don't create endless near-identical views.
6. A view can also be marked **global** (visible to every viewer, not just its author) instead of
   personal. A global view's stored filter can embed a placeholder token in place of a literal
   value — resolve it against the *current viewer's own* org id (or equivalent identity value)
   client-side, right after loading the view and before applying it to the grid, so one
   admin-authored view renders correctly for every viewer instead of needing a copy per org.

## Primary vs fallback

- **Primary — a personal view:** the default for "let each user save their own layout" — owned by,
  and only ever loaded by, the user who saved it.
- **Fallback — a global/shared view:** for "the standard view every user in an org should see,"
  authored once and readable by everyone. Switch to this when you'd otherwise have to create a
  near-identical personal view per user, and use the placeholder-substitution step above so it still
  scopes correctly per viewer.

## Minimal example

```ts
import { authFetch, getOneHealthBaseUrl } from "@/lib/auth-client"

interface GridConfiguration {
  columnState: { colId: string; hide: boolean; width: number }[]
  filterModel?: Record<string, unknown>
}

interface SavedView {
  id: string
  gridIdentifier: string
  name: string
  configuration: string // JSON-stringified GridConfiguration
}

// SAVE a new named view.
async function saveGridView(gridIdentifier: string, name: string, configuration: GridConfiguration) {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/v2/grid-config`, {
    method: "POST",
    body: JSON.stringify({ gridIdentifier, name, configuration: JSON.stringify(configuration) }),
  })
  if (!response.ok) throw new Error(`Save view failed: ${response.status}`)
  return response.json() as Promise<SavedView>
}

// LIST views for one grid — a fresh grid 404s; treat that as "zero views."
async function getGridViews(gridIdentifier: string, page = 0, size = 20): Promise<SavedView[]> {
  const baseUrl = getOneHealthBaseUrl()
  const params = new URLSearchParams({ gridIdentifier, page: String(page), size: String(size) })
  const response = await authFetch(`${baseUrl}/api/v2/grid-config?${params}`)
  if (response.status === 404) return []
  if (!response.ok) throw new Error(`List views failed: ${response.status}`)
  return (await response.json()).data ?? []
}

// Remember only the POINTER locally; the view itself lives in 1health.
function rememberLastViewId(gridIdentifier: string, viewId: string) {
  localStorage.setItem(`grid_view_${gridIdentifier}`, viewId)
}

// A GLOBAL view's filter can carry a placeholder in place of a literal value —
// substitute it with the current viewer's own org id before applying the view.
const VIEWER_ORG_PLACEHOLDER = "{{viewerOrgId}}"

function resolveGlobalViewFilters(configuration: GridConfiguration, viewerOrgId: string): GridConfiguration {
  const raw = JSON.stringify(configuration).replaceAll(VIEWER_ORG_PLACEHOLDER, viewerOrgId)
  return JSON.parse(raw)
}
```

## Gotchas

- `configuration` is an opaque string you JSON-stringify yourself — the platform doesn't validate its shape, so a malformed write only surfaces later when something tries to parse it back.
- A grid with no saved views yet returns **404**, not an empty list.
- One mapping table, both directions — translating UI-column-id ↔ platform-field-name ad hoc at each call site is how saved views quietly drift out of sync with the current grid.
- Only the last-applied view **id** belongs in `localStorage`, purely as a UX pointer. If it points at a view someone else deleted, fall back to the normal view list instead of erroring.
- Compare **visible** columns only when detecting duplicates — differences in hidden-column order/width shouldn't count.
- A global view's placeholder is resolved **client-side**, after the read — a caller that skips the
  substitution step applies the literal placeholder string as a filter value instead of the
  viewer's real org id.
- Reading a global view is open to any viewer; creating or editing one is presumably admin-gated
  even though the read isn't — don't assume a viewer who can select a global view can also change it.

## Related

- [bulk-tagging.md](bulk-tagging.md), [bulk-assignment.md](bulk-assignment.md) — actions typically launched from the same grid.
- [per-user-preferences.md](per-user-preferences.md) — contrast: this is shared view *definitions*; that recipe is smaller personal state.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md).
