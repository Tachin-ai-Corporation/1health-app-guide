# Save per-user preferences

**Use when:** you need state that belongs to a specific signed-in user (their recent items, a saved filter, a personal setting) rather than to a record that everyone who opens it shares.
**Routes:** resolve the caller's own Person id (a "who am I" call), then read/write that Person's `customData` — read via `POST /api/v2/query` · write via `POST /api/v2/data/custom-data/bulk` → [agents.md](https://agents.1health.io/public/prod/api/v2/data/custom-data/bulk/agents.md)
**Reference code:** [`lib/api/recently-viewed.ts`](https://github.com/Tachin-ai-Corporation/v0-trc-care-coordinator/blob/main/lib/api/recently-viewed.ts#L35)
**Seen in:** trc-care-coordinator (recently-viewed journeys stored on the signed-in user's own Person)

## Pattern

Both of the following are legitimate, for different jobs — pick by how durable the state needs to be:

1. **Durable, cross-device, or otherwise "real" per-user state** (recent items, saved filters that should follow the user, anything another part of your backend logic needs to read) → store it in 1health, on the **signed-in user's own `Person`** customData, namespaced under your `appData.<appId>` key.
2. **Pure per-viewer convenience that's fine to lose** (a collapsed panel, the last-used tab, an unsent draft) → `localStorage` is an acceptable, simpler alternative. No round trip, no risk of colliding with another app's namespace, and nothing is lost that mattered.
3. For the 1health path: resolve the caller's own `Person` id **once per session**, from a server-confirmed "who am I" call — never someone else's, and never a client-supplied id. This is state *about* the user, stored *on* the user.
4. Read the existing bucket, update it client-side (de-dupe, cap a list's length, merge fields), and write back with the deep-merge helper — the same shallow-`APPEND` footgun applies to a namespaced key on a Person exactly as it does anywhere else.
5. Cap unbounded lists (recent items, history) at a fixed size before writing — nothing server-side does it for you.

## Minimal example

```ts
import { readCustomData, mergeCustomData, appData } from "@/lib/api"

const MAX_RECENT = 20

/** The signed-in user's recently viewed record ids, most-recent-first. */
async function getRecentlyViewed(appId: string, personId: number): Promise<string[]> {
  const data = await readCustomData("Person", personId)
  const ids = (data.appData as Record<string, any> | undefined)?.[appId]?.recentlyViewed
  return Array.isArray(ids) ? ids.map(String) : []
}

/** Append one id, de-duped and capped, on the signed-in user's own Person. */
async function pushRecentlyViewed(appId: string, personId: number, id: string) {
  const existing = await getRecentlyViewed(appId, personId)
  const recentlyViewed = [id, ...existing.filter((x) => x !== id)].slice(0, MAX_RECENT)
  return mergeCustomData("Person", personId, appData(appId, { recentlyViewed }))
}

// A per-viewer convenience that need not survive a device change can just
// live in localStorage instead — no 1health round trip needed:
function setLastUsedFilter(filter: string) {
  try { localStorage.setItem("lastUsedFilter", filter) } catch { /* ignore */ }
}
```

## Gotchas

- Always resolve the **signed-in user's own** Person id from a server-confirmed call — never trust a client-supplied person id for "whose preferences are these."
- This is still a nested/namespaced `customData` write — use the deep-merge helper (`mergeCustomData`), not a raw `APPEND`, or you'll wipe sibling `appData` keys, including other apps' data on a shared Person. See [read-write-custom-data.md](read-write-custom-data.md).
- Don't reach for `localStorage` for anything that must be visible on a second device, or that your own backend logic needs to read — it's invisible to 1health and to every other client.
- Cap array-shaped preferences before writing; an unbounded recent-items list will grow every session.

## Related

- [read-write-custom-data.md](read-write-custom-data.md) — the deep-merge mechanics.
- [write-safety-and-fail-closed.md](write-safety-and-fail-closed.md) — apply the same fail-closed discipline if preferences can be read-modify-written from multiple tabs at once.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md) (§ customData).
