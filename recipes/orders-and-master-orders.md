# Create, advance, and read orders and master orders

**Use when:** a patient (or an external storefront) is placing one or more tests/products, you
need to track a multi-item checkout as a unit, you need to cancel/reject/force-complete an order,
read one back, or track a physical kit's fulfillment.
**Routes:** `POST /api/v2/health/order` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/order/agents.md) · `POST /api/v2/health/order/e-commerce` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/order/e-commerce/agents.md) · `PUT /api/v2/health/order/{orderId}` (outcome) → [agents.md](https://agents.1health.io/public/prod/api/v2/health/order/agents.md) · `GET /api/v2/health/order/{id}/details` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/order/_id_/details/agents.md) · `GET /api/v2/health/order/{id}/full-template` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/order/_id_/full-template/agents.md) · `GET /api/v2/health/master-order/{id}/details` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/master-order/_id_/details/agents.md) · `DELETE /api/v2/health/order/{id}/kits` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/order/_id_/kits/agents.md) · `GET /api/v2/organization/test-product/{testProductCode}/kit/{kitKey}/shipments` → [agents.md](https://agents.1health.io/public/prod/api/v2/organization/test-product/_testProductCode_/kit/_kitKey_/shipments/agents.md) · order-keyed journey aliases and kit registration (not yet in the published docs — see banner)
**Reference code:** none public — see the Minimal example
**Seen in:** 1health platform usage

> **⚠ Not yet in 1health's published API docs:** the order-keyed journey aliases
> (`GET /api/v2/health/order/{orderId}/journey`, `GET .../order/{orderId}/step/{stepId}/info`,
> `POST .../order/{orderId}/step/{stepId}/submit`, `GET .../order/{orderId}/documents`) and kit
> registration (`POST /api/v2/kit/register`, `POST /api/v2/health/kit/{id}`). 1health supports them
> for third-party apps, but agents.1health.io has no page for them yet — the shapes shown here come
> from working apps. Test them against demo before you rely on them.

## Pattern

1. Model a multi-item checkout as one **MasterOrder** wrapping N **Order** records, one per line
   item — never force multiple tests onto a single Order's own fields. A MasterOrder carries no
   clinical fields of its own: an id, a status, the grouped orders, and (for the e-commerce path) a
   cart reference. Each grouped Order still has its own workflow/journey and outcome — grouping is
   a checkout convenience, not a merged lifecycle.
2. Create through whichever entry point matches who's placing the order — see Primary vs fallback.
3. Treat cancel/reject/force-complete as its **own transition** on the order resource, not a step
   submission — it sits entirely outside the step-advancement mechanism ([workflows-journeys-steps.md](workflows-journeys-steps.md)).
4. Remember an order and its journey are **different records with different ids**. Placing an
   order implicitly starts a journey instance, and the order carries that journey's id as its own
   field — see Primary vs fallback for which routes to use.
5. Read an order through whichever **view** matches your need: `details` for a general-purpose
   read, `full-template` for the step/workflow tree, and a MasterOrder's own `details` for the
   checkout as a whole. These are different views over overlapping data, not a hierarchy — don't
   assume one supersedes another.
6. During intake, resolve the patient before creating the order: run the scored find
   ([patient-find.md](patient-find.md)) first, and only create a new patient via v3
   ([patient-crud.md](patient-crud.md)) when there's no acceptable match — confirming it's attached
   to your organization before ordering against it ([deferred-record-creation.md](deferred-record-creation.md)).
7. Track a physical kit's fulfillment as its own sub-lifecycle: assigning an outbound
   carrier/tracking is one event, logging a return/inbound tracking code is another — not a single
   "shipped" boolean. Read a kit's shipment history by test-product code + kit key, not the kit's
   own numeric id. Deleting an order's kits also removes their inbound shipment record — no
   separate cleanup call is needed. Issuing/registering a kit instance itself is a separate,
   undocumented action (see banner) — distinct from the catalog CRUD in
   [catalog-vs-instance-modeling.md](catalog-vs-instance-modeling.md).
8. When a test's underlying catalog entry is a panel (bundles sub-tests), explicitly list which
   sub-tests to include — ordering the parent doesn't implicitly order every component (see
   [test-catalog-modeling.md](test-catalog-modeling.md)).

## Primary vs fallback

**Creating an order**
- **Primary — `POST /api/v2/health/order`:** the normal clinical flow, one patient + test product
  per call.
- **Fallback — `POST /api/v2/health/order/e-commerce`:** an external storefront placing several
  products for a buyer, referenced by product code, tagged with its own shopping-cart order
  number. Switch to this only when an outside cart system — not 1health — is the source of truth
  for what's in the cart.

**Reaching an order's journey, steps, or documents**
- **Primary — the generic `journey/{journeyId}/...` family** ([workflows-journeys-steps.md](workflows-journeys-steps.md)):
  resolve the order's own `journeyId` (off its grid row or `details` read) first, then advance/read
  steps and documents exactly as you would for a campaign-sourced journey.
- **Fallback — the order-keyed aliases** (banner above): use only when you hold an order id and
  haven't resolved its `journeyId` yet. Prefer resolving `journeyId` and switching to the primary
  family as soon as you can — the order id and the journey id are both plain numbers in the same
  space, so passing the wrong one can silently target the wrong record instead of 404ing.

## Minimal example

```ts
import { authFetch, getOneHealthBaseUrl } from "@/lib/auth-client"

// PRIMARY create — one clinical order.
async function placeClinicalOrder(orderLines: Array<{ patientId: number; testProductId: number }>) {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/v2/health/order`, {
    method: "POST",
    // Per-line-item fields aren't spelled out in the published docs beyond this array wrapper —
    // confirm the exact shape by inspecting a created order in demo before shipping.
    body: JSON.stringify({ orders: orderLines }),
  })
  if (!response.ok) throw new Error(`Create failed: ${response.status}`)
}

// A MasterOrder groups the resulting Orders for a multi-line checkout.
interface MasterOrderDetails {
  id: number
  status: string
  orders: Array<{ id: number; journeyId: number }>  // each grouped Order keeps its own journey
}

async function fetchMasterOrder(masterOrderId: number): Promise<MasterOrderDetails> {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/v2/health/master-order/${masterOrderId}/details`)
  if (!response.ok) throw new Error(`Fetch failed: ${response.status}`)
  return response.json()
}

// Cancel / reject / force-complete: its own transition, never a step submit. The exact accepted
// `outcome` strings aren't spelled out in the published docs — confirm the exact casing against
// demo before shipping.
async function closeOrderWithOutcome(orderId: number, outcome: string) {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/v2/health/order/${orderId}?outcome=${outcome}`, {
    method: "PUT",
  })
  if (!response.ok) throw new Error(`Outcome update failed: ${response.status}`)
}

// Kit fulfillment: shipment history is keyed by test-product code + kit key, not the kit's id.
async function fetchKitShipments(testProductCode: string, kitKey: string) {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(
    `${baseUrl}/api/v2/organization/test-product/${testProductCode}/kit/${kitKey}/shipments`,
  )
  if (!response.ok) throw new Error(`Fetch failed: ${response.status}`)
  return response.json()
}
```

## Gotchas

- **An order's own id and its `journeyId` are different numbers in the same id space** — mixing
  them up doesn't necessarily fail loudly; it can silently target the wrong record.
- **A test-offered panel's sub-tests aren't implicitly ordered** — list which components to
  include explicitly.
- **Deleting an order's kits also removes their inbound shipment record** — don't build separate
  cleanup for it.
- **The outcome transition is for operator/administrative actions** — don't build "cancel" as a
  fake step in a journey template; it's a first-class transition orthogonal to the step tree.
- **Order reads are different views, not a hierarchy** — pick `details`, `full-template`, or a
  MasterOrder's `details` by what you actually need, not by assuming one is "more complete."

## Related

- [workflows-journeys-steps.md](workflows-journeys-steps.md) — the journey/step mechanics once you
  have the order's `journeyId`.
- [patient-find.md](patient-find.md) · [patient-crud.md](patient-crud.md) — resolving or creating
  the patient before creating an order.
- [catalog-vs-instance-modeling.md](catalog-vs-instance-modeling.md) — the kit catalog/instance
  split behind kit fulfillment.
- [test-catalog-modeling.md](test-catalog-modeling.md) — what you're actually ordering.
- [comments.md](comments.md) — case notes scoped by this order's own id.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
