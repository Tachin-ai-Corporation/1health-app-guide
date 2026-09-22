# Write a raw BOI instance attribute

**Use when:** you need to write an attribute that no typed REST endpoint exposes — some verification flag or note field that exists only as a raw attribute on the business-object instance.
**Routes:** `GET/PUT /api/v1/boi/{id}` → [manifest](https://agents.1health.io/public/prod/api/manifest.md) (confirm the exact doc path there)
**Reference code:** [`lib/api/contact-points.ts`](https://github.com/Tachin-ai-Corporation/v0-trc-care-coordinator/blob/main/lib/api/contact-points.ts#L148) (`verifyContactPoint`)
**Seen in:** trc-care-coordinator (writing verification attributes on a ContactPoint instance)

## Pattern

1. Treat this as an **escape hatch**, not a default — reach for it only once you've confirmed the object's typed REST surface genuinely has no route for the field you need to set.
2. `GET /api/v1/boi/{id}?dataView=full` returns the instance's full attribute list; each entry carries a stable `attribute.key` string and a per-tenant numeric `attribute.id`.
3. **Resolve the numeric attribute id by matching `attribute.key`** on every call — never hardcode the numeric id, since it's schema-specific and differs across tenants/environments.
4. `PUT /api/v1/boi/{id}` with `{ attributes: { "<numericId>": "<value>" } }` is a **sparse patch** — only the keys you include are touched; everything else on the instance is left alone.
5. Every attribute value is sent as a **string**, including booleans (`"true"`/`"false"`) — the endpoint is type-validated server-side and rejects a JSON boolean/number where it expects a string.

## Minimal example

```ts
import { callApi } from "@/lib/api"

interface BoiAttribute { attribute?: { id?: number; key?: string } }

/** Resolve a per-tenant numeric attribute id by its stable string key. */
async function resolveAttributeId(instanceId: number, key: string): Promise<number | undefined> {
  const res = await callApi<{ attributes: BoiAttribute[] }>("boi/read", `/api/v1/boi/${instanceId}?dataView=full`)
  return res.data?.attributes?.find((a) => a.attribute?.key === key)?.attribute?.id
}

/** Sparse-patch raw attributes by key. Values are always sent as strings. */
async function writeBoiAttributes(instanceId: number, patch: Record<string, string>) {
  const attributes: Record<string, string> = {}
  for (const [key, value] of Object.entries(patch)) {
    const id = await resolveAttributeId(instanceId, key)
    if (id == null) throw new Error(`Instance ${instanceId} has no attribute "${key}"`)
    attributes[String(id)] = value
  }
  return callApi("boi/write", `/api/v1/boi/${instanceId}`, {
    method: "PUT",
    body: JSON.stringify({ attributes }),
  })
}

await writeBoiAttributes(contactPointId, { isVerified: "true", verifiedNote: "Confirmed by phone" })
```

## Gotchas

- Never hardcode a numeric attribute id — resolve it from `attribute.key` on every call (or cache per-tenant, never globally); the same field has different ids in demo vs. prod.
- **Booleans are strings here.** Sending JSON `true` is rejected ("Expecting boolean value ... got Boolean") — send `"true"`/`"false"`.
- Check first whether a typed REST endpoint already covers your field. Some fields that look like they'd need this are actually set as a side effect of a normal typed write, and a raw BOI write competing with that is redundant and easy to get out of sync with it.
- The write is a sparse patch, not a full replace — don't send attributes you're not changing.

## Related

- [read-write-custom-data.md](read-write-custom-data.md) — prefer `customData` for app-owned state; reach for this only for a platform attribute with no typed route.
- [query-the-data-graph.md](query-the-data-graph.md) — the normal, typed way to read platform attributes.
- [../api/README.md](../api/README.md)
