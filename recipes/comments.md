# Comments

**Use when:** you need a lightweight discussion thread on a journey — case notes, coordination chatter — without inventing your own comment type.
**Routes:** list via `POST /api/v3/health/grid/comment` → [agents.md](https://agents.1health.io/public/prod/api/v3/health/grid/comment/agents.md) · post via `POST /api/v2/journey/_journeyId_/comment` → [route docs](https://agents.1health.io/public/prod/api/manifest.md)
**Reference code:** [`lib/api/journey-comments.ts`](https://github.com/Tachin-ai-Corporation/v0-trc-care-coordinator/blob/main/lib/api/journey-comments.ts)
**Seen in:** trc-care-coordinator (also a template-baseline capability; seen too in med-adherence)

## Pattern

1. Comments are **not** read via `/query` — list them through the **grid** endpoint family, filtered to one journey, the same family used for list/table views.
2. Post through the journey's own comment endpoint. The body wraps comments in an **array**, even when posting exactly one.
3. Sort newest-first server-side (`orderBy` on `updated`, `DESC`) rather than pulling everything and sorting client-side.
4. Read the grid response defensively — rows arrive under a `data` field; guard for it being empty or missing rather than assuming a fixed shape.

## Minimal example

```ts
import { authFetch, getOneHealthBaseUrl } from "@/lib/auth-client"

interface Comment {
  id: number
  content: string
  created: string
  ownerFirstName: string | null
  ownerLastName: string | null
}

// LIST — via the grid family, not /query.
async function fetchJourneyComments(journeyId: number): Promise<Comment[]> {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/v3/health/grid/comment?page=0&size=20`, {
    method: "POST",
    body: JSON.stringify({
      filterBy: [{ key: "journeyId", operator: "equals", value: journeyId }],
      orderBy: [{ key: "updated", order: "DESC" }],
    }),
  })
  if (!response.ok) throw new Error(`Fetch failed: ${response.status}`)
  const body = await response.json()
  return body.data ?? []
}

// POST — body wraps an array, even for a single comment.
async function postJourneyComment(journeyId: number, content: string): Promise<void> {
  const baseUrl = getOneHealthBaseUrl()
  const response = await authFetch(`${baseUrl}/api/v2/journey/${journeyId}/comment`, {
    method: "POST",
    body: JSON.stringify({ comments: [{ content }] }),
  })
  if (!response.ok) throw new Error(`Post failed: ${response.status}`)
}
```

## Gotchas

- Comments aren't a `/query`-able type in practice — use the grid endpoint even for a single-journey read.
- The post body's `comments` field is an **array** — posting `{ content }` unwrapped fails.
- A grid validation error can still come back with a normal 4xx status and a useful message body — check `response.ok` and surface it rather than assuming any non-throw means success.
- `ownerFirstName`/`ownerLastName`/`ownerEmail` can be `null` when the platform can't resolve the commenting identity — render a fallback label instead of blank space.

## Related

- [attachments.md](attachments.md) — the other collaboration primitive on a journey.
- [query-the-data-graph.md](query-the-data-graph.md) — contrast: most reads go through `/query`; this one deliberately doesn't.
- Concepts: [setup/rules-of-the-road.md](../setup/rules-of-the-road.md).
