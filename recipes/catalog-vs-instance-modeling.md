# Separate a catalog definition from the instances created from it

**Use when:** you're modeling anything a user can pick from a list (a test, a kit, a supply item)
alongside anything that gets created when they pick it (an order, an issued kit, a submitted
result) — decide which is which before you design the schema.
**Routes:** `GET/PUT/DELETE /api/v2/health/kit/{id}` (+ `POST /api/v2/health/kit` to create) → [agents.md](https://agents.1health.io/public/prod/api/v2/health/kit/agents.md) · `GET/POST/PUT/DELETE /api/v2/test-offered/{id}/collection-specification/{specId}` (not yet in the published docs) · `POST/PUT/DELETE /api/v2/health/supply-product/{id}/bom/{bomId}` (not yet in the published docs)
**Reference code:** none public — see the Minimal example
**Seen in:** 1health platform usage

> **⚠ Not yet in 1health's published API docs:** `GET/POST/PUT/DELETE /api/v2/test-offered/{id}/collection-specification/{specId}` and `POST/PUT/DELETE /api/v2/health/supply-product/{id}/bom/{bomId}`. 1health supports them for third-party apps, but agents.1health.io has no page for them yet — the shapes shown here come from working apps. Test them against demo before you rely on them.

## Pattern

1. Ask "is this a thing a user can pick, or something that happened as a result of picking it?" A
   test/kit/supply-item **type** is the former (catalog); an order, an issued kit, a submitted
   result is the latter (**instance**).
2. Model the catalog entry as its own typed record carrying definitional facts: pricing/identity
   codes (SKU, UPC), manufacturer, an activation/deactivation availability window.
3. Model the instance as a separate record that **references the catalog entry by id** — never
   nests or copies its fields — and carries only what's true of this specific use: its own
   lifecycle status and, when physical, its own serialized key/barcode.
4. When part of a catalog entry is itself structured — what to collect for a test, what parts make
   up a kit — give it a **nested typed sub-resource** scoped under the catalog entry's own id,
   rather than flattening it into the parent record or reaching for a schemaless blob.
5. Let a sub-resource line reference another catalog entry's id for composition (a
   bill-of-materials line points at a component item) instead of copying that item's own fields —
   composition nests without denormalizing cost/manufacturer data everywhere it's used.

## Minimal example

```ts
import { authFetch, getOneHealthBaseUrl } from "@/lib/auth-client"

// CATALOG — "a kit you can offer." Pricing/identity facts that don't change per use.
interface KitCatalogEntry {
  id: number
  name: string
  sku: string
  manufacturer?: { id: number; name: string }
  cost: number
}

async function fetchKitCatalogEntry(kitId: number): Promise<KitCatalogEntry> {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/v2/health/kit/${kitId}`)
  if (!response.ok) throw new Error(`Fetch failed: ${response.status}`)
  return response.json()
}

// INSTANCE — "a kit that was actually issued." References the catalog entry by id;
// carries its own barcode and lifecycle instead of copying the catalog's fields.
interface IssuedKit {
  id: number
  kitCatalogId: number
  serializedKey: string
  orderId: number
  status: string
}

// A catalog sub-resource (e.g. a test's collection requirements) is scoped under the parent
// catalog entry's own id — its own typed CRUD family, not a customData field:
//   GET/POST/PUT/DELETE /api/v2/test-offered/{testOfferedId}/collection-specification/{specId}
// (not yet in the published docs — see the banner above; confirm the exact body against demo)
```

## Gotchas

- **A catalog entry's own SKU/UPC is typically unique only within its own supplier scope** — don't
  assume it's globally unique the way an issued instance's barcode is expected to be (and even
  then, only for the window it's actively in use).
- **A nested catalog sub-resource is its own typed CRUD family scoped under the parent id** — it
  isn't reachable through the generic customData mechanism, so don't bolt collection requirements
  or a bill of materials onto customData instead.
- **The instance never inlines the catalog entry's fields** — if you find yourself copying
  price/manufacturer/SKU onto the instance record "for convenience," that data belongs in a
  reference back to the catalog id, not a duplicate.

## Related

- [orders-and-master-orders.md](orders-and-master-orders.md) — an order is the instance created
  when a test-product is purchased.
- [test-catalog-modeling.md](test-catalog-modeling.md) — the same catalog/instance split,
  specialized to diagnostic tests.
- [read-write-custom-data.md](read-write-custom-data.md) — contrast: why a structured sub-resource
  beats flattening into customData here.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
