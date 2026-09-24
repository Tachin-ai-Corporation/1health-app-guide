# Cohort conditions: the filter catalog, operators, and value encoding

**Use when:** you're building the condition editor of a cohort builder, where the user picks a filter, an operator, and a value. It also covers reading a saved definition back into that editor, and reusable filter-group templates.

**Routes:**
- the filter catalog: `GET /api/v2/health/order/data-definition/list` → [agents.md](https://agents.1health.io/public/prod/api/v2/health/order/data-definition/list/agents.md)
- value-list options: `GET /api/v2/type/key/{typeName}` → [agents.md](https://agents.1health.io/public/prod/api/v2/type/key/agents.md)
- templates: `POST /api/v2/filter-group/template` and `DELETE …/{id}` → [agents.md](https://agents.1health.io/public/prod/api/v2/filter-group/template/agents.md)
- read-back and template lists: `POST /api/graphql` → [agents.md](https://agents.1health.io/public/prod/api/graphql/agents.md)

**Reference code:** none public; see the Minimal example.
**Seen in:** 1health platform usage. The catalog, operators, value encodings, and read-back query were verified on demo.

## Pattern

1. **Let the catalog drive the editor.** Call `GET /api/v2/health/order/data-definition/list?workflowType=Cohort Definition`.
   It returns every filterable field as
   `{ id, name, category, type, typeKey, attributeKey, attributePath, comparisonOperators[] }`.
   Build a cascade from it:
   - category;
   - definition;
   - operator, offering only *that definition's* `comparisonOperators`;
   - a value input chosen by `type`.

   Don't hardcode the list: it varies by tenant and grows. On demo it returned 22 definitions in
   4 categories:

   | Category | Definitions |
   |---|---|
   | Care Gap | Active Date, Open Care Gaps, Status, Measurement Year, Measure |
   | Care Quality Data (CQD) | Evidence Date, Evidence Type |
   | Insurance Policy | Employer Group Number, Eligibility Date, Plan Type, PBP ID, Network Type, Contract ID, Region, Active Status |
   | Member (Patient) | Birthdate, State, Zipcode, Race, Ethnicity, Biological Gender, Tags |

2. **Know the shapes.**
   - A condition is `{ definitionId, comparisonOperator, order, value }`.
   - A group is `{ name, order, logicalOperator: "AND" | "OR", conditions }`.
   - `order` is the 0-based position, so reordering by drag and drop is just renumbering.
   - Conditions inside a group are AND-ed. A group's `logicalOperator` joins it to the groups before it.
3. **Encode `value` by the definition's `type` and the operator:**

   | `type` | Operators (as the catalog returns them) | `value` |
   |---|---|---|
   | `int` | Greater Than, Greater Than Or Equal To, Less Than, Less Than Or Equal To, Equal To | a number |
   | `int` | Between (inclusive), Between Exclusive | `{ start, end }` numbers |
   | `date` | Greater Than (after), Less Than (before), Equal To (on) | the day at UTC midnight, `"2025-01-01T00:00:00.000Z"` |
   | `date` | Between (on or between), Between Exclusive | `{ start, end }` dates, same format |
   | `text`, `value list` | Is Any Of These, Is All Of These, Is Not Any Of These, Has Only Any Of These, Has Only All Of These | an array of strings |
   | `text`, `value list` | Is Empty | `[]` |

   Some fields expect a different value than what the user sees:
   - **Measurement Year** (`int`) is a multi-select: send an array of year strings, e.g. `["2025"]`.
   - **Evidence Type** (`int`) takes an array of evidence-definition **ids**. The user picks names;
     the ids and names come from the `CareQualityDataEvidenceDefinition` records.
   - **State** takes **two-letter codes**, e.g. `["TX"]`, even though the attribute is `stateName`.
   - **Active Status** (the insurance label) takes `"Active"` or `"Expired"`. Label `"Expired"`
     however suits your users, for example "Inactive".
   - **Measure** takes quality-measure codes. Load the options from the tenant's `QualityMeasure`
     records (their `name`, per `measurementYear`) rather than a hardcoded list, which drifts.
4. **Load value-list options from the schema.** Call `GET /api/v2/type/key/{typeKey}`, take the
   attribute whose `attrKey` equals the definition's `attributeKey` and whose `atrbType` is
   `"value list"`, and read its `attributeValues[].name`, dropping the `"n/a"` sentinel. This covers
   Race, Ethnicity, Biological Gender, Plan Type, Network Type, Region, and care-gap Status. Other
   `text` fields (Zipcode, Contract ID, Employer Group Number, …) are free entry.
5. **Read a saved definition back through GraphQL**; there's no REST read. When decoding:
   - `state`, `logicalOperator`, and `comparisonOperator` (and a definition's `category`) come back
     as **arrays**, so take `[0]`;
   - `value` comes back as a **string**. For example, a date range is stored as
     `{"start":"1980-01-01T00:00:00.000Z","end":"1980-01-07T00:00:00.000Z"}`. JSON-parse arrays and
     `{ start, end }` ranges, and leave a single number or date as it is;
   - a condition's `name` comes back as `"n/a"`, because nothing sends one;
   - map codes back to labels (state codes to names, evidence ids to names).
6. **Treat templates as reusable groups** (the round trip below was verified on demo).
   - **Save:** `POST /api/v2/filter-group/template` with the same group body. The template is
     created with `isPublic: true`, even if you don't send the field.
   - **List:** GraphQL `ConditionFilterGroup(filter: { isPublic: { equal: true }, searchText: … })`,
     paged with `{ limit, offset }`; `recordsCount` gives you the last page.
   - **Apply:** copy the template's conditions into a new group. It's a copy, not a link.
   - **Delete:** `DELETE /api/v2/filter-group/template/{id}`, which returns `200` with an empty body.

   Templates belong to the organization that saved them.

## Minimal example

```ts
type Definition = { id: number; type: "int" | "date" | "text" | "value list"; attributeKey: string; comparisonOperators: string[] }

const RANGE_OPERATORS = new Set(["Between", "Between Exclusive"])
const MULTI_SELECT_INTS = new Set(["measurementYear", "evidenceDefinitionId"]) // ints sent as arrays
const utcMidnight = (day: Date) => new Date(Date.UTC(day.getFullYear(), day.getMonth(), day.getDate())).toISOString()

// One editor row → one condition. `input` is already mapped to codes/ids where the field needs it.
export function toCondition(def: Definition, operator: string, input: any, order: number) {
  if (!def.comparisonOperators.includes(operator)) {
    throw new Error(`"${operator}" isn't an allowed operator for this filter`) // exact and case-sensitive
  }
  let value: unknown
  if (def.type === "int" && !MULTI_SELECT_INTS.has(def.attributeKey)) {
    value = RANGE_OPERATORS.has(operator) ? { start: Number(input.start), end: Number(input.end) } : Number(input)
  } else if (def.type === "date") {
    value = RANGE_OPERATORS.has(operator) ? { start: utcMidnight(input.start), end: utcMidnight(input.end) } : utcMidnight(input)
  } else {
    value = operator === "Is Empty" ? [] : input // an array of strings (or ids)
  }
  return { definitionId: def.id, comparisonOperator: operator, order, value }
}

// Read-back: one definition's tree through GraphQL (there's no REST GET for a definition).
export const cohortDefinitionQuery = (id: number) => `query {
  CohortDefinition(filter: { id: { equal: ${id} } }) { records {
    id name description state measurementYear
    CohortDefinitionHasConditionFilterGroup { relations { record {
      id name order logicalOperator
      ConditionFilterGroupHasDataFilterCondition { relations { record {
        id order value comparisonOperator
        DataFilterConditionHasDataFilterDefinition { relations { record { id name category } } }
      } } }
    } } }
    CohortDefinitionInitiatesWorkflowCampaign { relations { record { id } } }
  } }
}`

// Decode one stored condition.
export function fromStored(record: { value: string; comparisonOperator: string[] }) {
  let value: unknown = record.value
  try { value = JSON.parse(record.value) } catch { /* a single date stays a string */ }
  return { operator: record.comparisonOperator[0], value }
}
```

## Gotchas

- **Operators are exact, case-sensitive, and per definition.** Offer only the definition's own
  `comparisonOperators`. Not every multi-select supports "Is Empty" or "Is All Of These", and some
  support only "Is Any Of These" and "Is Not Any Of These". `"is any of these"` is a `400`
  "Invalid comparison operator".
- **This is its own dialect.** It isn't the RSQL that `/query` uses, and it isn't the grid's
  `equals`/`greaterThan` operators. Don't port conditions between the three.
- **Dates:** send UTC midnight of the calendar day the user picked. The API also accepted plain
  `YYYY-MM-DD` on demo. On read-back, take the date part and don't shift it through local time, or
  the day moves.
- **Build inputs only for what the catalog returns.** Categories differ by tenant, and demo's
  catalog has no claims or clinical-record conditions.
- **Multi-select values are labels, not ids,** except the id-backed fields above (Evidence Type).
  The State field takes codes.
- **A template doesn't stay linked to the groups made from it,** so editing or deleting it leaves
  existing cohorts unchanged.

## Related

- [cohort-definitions.md](cohort-definitions.md) — the lifecycle this editor feeds.
- [schema-discovery.md](schema-discovery.md) — `GET /type/key/{typeName}` for value lists.
- [graphql-read-path.md](graphql-read-path.md) — GraphQL filters, paging, and relation reads.
- [sentinel-values-not-null.md](sentinel-values-not-null.md) — `"n/a"` in value lists; coded fields as arrays.
