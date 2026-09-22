# In-app agent-docs mirror

> **Advanced / guardrailed pattern.**

**Use when:** you want to surface live 1health API reference docs inside your own app's UI (or as a machine-readable endpoint for an agent working inside your app) instead of sending readers off to the docs host.
**Routes:** n/a — this proxies the public docs host (`agents.1health.io`), not the 1health object-graph API; see [api/README.md](../api/README.md) for the docs bridge itself.
**Reference code:** [`lib/docs.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/docs.ts), [`app/api/agent-docs/route.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/app/api/agent-docs/route.ts)
**Seen in:** patient-vault

## Pattern

1. Search the docs host's canonical search endpoint for the specific routes your app actually surfaces (a fixed, small query list) — don't try to mirror the entire API surface.
2. **Before fetching any doc URL the search response hands you, validate it against an origin + path allowlist** — exact origin match, path must start with the expected public-docs prefix and end with the expected doc filename. This is the SSRF defense: the URL came from a network response, not your own code, so it must be verified before your server fetches it.
3. Only after validation, fetch the doc content server-side with a short revalidation cache window, so it stays live without hitting the docs host on every request.
4. Strip frontmatter and parse out whatever structure you need (e.g. a `## METHOD /path` index); rewrite cross-doc links to point at your own app's doc-viewer route, not back at the docs host.
5. Expose one server route taking an environment + a slug, returning the loaded doc as JSON — the same loader backs both a human-facing docs UI and any machine/agent-facing consumer.

## Minimal example

```ts
const DOCS_ORIGIN = "https://agents.1health.io"

/** SSRF gate: only a URL that is actually this exact origin + expected shape is fetched. */
function validSourceUrl(value: string, environment: "demo" | "prod"): string | null {
  try {
    const url = new URL(value)
    if (url.origin !== DOCS_ORIGIN) return null
    if (!url.pathname.startsWith(`/public/${environment}/api/`) || !url.pathname.endsWith("/agents.md")) return null
    return url.toString()
  } catch {
    return null
  }
}

export async function loadDoc(environment: "demo" | "prod", query: string) {
  const search = await fetch(`${DOCS_ORIGIN}/api/v1/docs/search?env=${environment}&q=${encodeURIComponent(query)}`,
    { next: { revalidate: 300 } })
  const { results } = await search.json()
  const hit = results.find((r: any) => validSourceUrl(r.agents_md_url, environment))   // gate BEFORE fetching
  if (!hit) return null
  const doc = await fetch(validSourceUrl(hit.agents_md_url, environment)!, { next: { revalidate: 300 } })
  return doc.text()
}
```

## Gotchas

- **Validate origin AND path AND suffix**, not just "starts with the expected host string" — a loose substring check can be satisfied by a URL that merely embeds the expected text elsewhere.
- **Never forward the caller's own URL input straight into the fetch** — only URLs your own search call returned, and only after the allowlist, are ever fetched.
- **Cache with a short revalidation window**, not indefinitely — the source docs change as 1health ships new routes.

## Related

- [api/README.md](../api/README.md)
- [knowledge-base-proxy.md](knowledge-base-proxy.md)
- [public-reference-api-proxy.md](public-reference-api-proxy.md)
