# Separate a test's clinical definition from its commerce listing

**Use when:** you're cataloging a diagnostic test for ordering — decide what belongs on the
clinical/lab definition, what belongs on the sellable product wrapper around it, and when a scored
overlay is really a third, narrower thing.
**Routes:** `GET/POST/PUT/DELETE /api/v2/test-offered` → [agents.md](https://agents.1health.io/public/prod/api/v2/test-offered/agents.md) · `GET/POST/PUT/DELETE /api/v2/health/test-product` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/test-product/agents.md) · `GET /api/v2/academic-test` → [agents.md](https://agents.1health.io/public/prod/api/v2/academic-test/agents.md) · `POST /api/v2/health/order/{orderId}/step/{wfStepId}/academic-test-score` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/order/_orderId_/step/_wfStepId_/academic-test-score/agents.md)
**Reference code:** none public — see the Minimal example
**Seen in:** 1health platform usage

## Pattern

1. Put clinical/fulfillment facts on the **test-offered** entry: specimen collection method,
   transport container, applicable diagnosis/procedure codes (`defaultIcd`, `cptCode`), and whether
   it's a **panel** bundling other tests (`isPanel` + `testOfferedComponents`).
2. Put commerce/availability facts on a separate **test-product** entry that references the
   test-offered: price/currency, which organizations can buy it (`availableToOrganizations`),
   consent requirements, and which workflow template family drives its ordering journey
   (`workflowTemplateGroup`).
3. Read a test-product's own config flags to decide which steps the resulting order's journey
   should show — who answers the intake questionnaire (patient or provider), whether a provider
   must approve report release before it's visible — rather than hardcoding a step sequence per test.
4. Treat a scored "academic test" overlay as its own narrow vertical: a rubric attached to specific
   test-offered ids for one clinical-scoring use case, not a general modeling pattern to reuse for
   other kinds of tests.
5. When ordering a panel, explicitly list which of its component sub-tests to include — ordering
   the parent test-offered doesn't implicitly order every component.
6. Both catalog levels carry their own availability window (`isActive`, `releaseDate`,
   `retirementDate` on test-offered) — check these before presenting a test as orderable,
   independent of whether the product wrapper is otherwise configured.

## Minimal example

```ts
import { authFetch, getOneHealthBaseUrl } from "@/lib/auth-client"

// Clinical/lab definition — specimen handling, codes, panel structure.
interface TestOffered {
  id: number
  name: string
  isPanel: boolean
  testOfferedComponents?: Array<{ id: number; name: string }>
  isActive: boolean
}

// Commerce wrapper — price, visibility, and which config drives the ordering journey.
interface TestProduct {
  id: number
  price: number
  currency: { code: string }
  workflowTemplateGroup: { id: number; name: string }
  patientAnswersQuestionnaire: boolean
  healthProviderApprovesReportRelease: boolean
  isActive: boolean
}

async function fetchOrderableTestProducts(): Promise<TestProduct[]> {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/v2/health/test-product?page=0&size=50`)
  if (!response.ok) throw new Error(`Fetch failed: ${response.status}`)
  const body = await response.json()
  return (body.data ?? []).filter((p: TestProduct) => p.isActive)
}

// Ordering a panel: list which components to include — the parent id alone isn't enough.
// (The exact field name for the selected components at order time isn't spelled out in the
// published docs — confirm it by inspecting a created panel order in demo.)
function buildPanelOrderLine(testOffered: TestOffered, selectedComponentIds: number[]) {
  if (!testOffered.isPanel) return { testOfferedId: testOffered.id }
  return { testOfferedId: testOffered.id, selectedComponents: selectedComponentIds }
}
```

## Gotchas

- **A panel's `testOfferedComponents` only tells you what *can* be included** — ordering the panel
  still requires the caller to say which components to actually include; nothing is implied.
- **`isActive`/`releaseDate`/`retirementDate` live on the test-offered, not the test-product** — a
  product can look fully configured while its underlying test is outside its availability window.
- **Don't assume the academic-test scoring overlay generalizes to other test kinds** — it's a
  narrow, purpose-built vertical (its score endpoint takes explicit `testOfferedIds` +
  `medicalCodeIds`, not a generic "any test" scoring contract).
- **A test-product's questionnaire/report-approval flags decide the shape of the
  resulting order's journey** — read them at order-build time rather than caching a step sequence
  per test.

## Related

- [catalog-vs-instance-modeling.md](catalog-vs-instance-modeling.md) — the catalog/instance split
  this test hierarchy is one example of.
- [orders-and-master-orders.md](orders-and-master-orders.md) — ordering a test-product, once chosen.
- [results-ingestion.md](results-ingestion.md) — what a test-offered's result looks like once
  submitted.
- [workflows-journeys-steps.md](workflows-journeys-steps.md) — the journey a test-product's config
  shapes.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
