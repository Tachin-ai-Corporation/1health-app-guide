# Demo-mode seam

> **Advanced / guardrailed pattern.**

**Use when:** you need a fully-functional demo of your app (same components, same workflow) running against **invented data**, possibly side-by-side with a real session in another tab, without ever touching the real session's cookies.
**Routes:** n/a — an auth/session-layer seam; the demo path answers its own requests instead of calling 1health at all.
**Reference code:** [`lib/demo/demo-session.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/demo/demo-session.ts)
**Seen in:** pcp-tcm

## Pattern

1. Do **not** write demo credentials into `document.cookie` — that's the same storage a real session on the same origin uses, so a demo tab could silently log out or corrupt a real session open next to it.
2. Instead, hold the demo "session" (token, base URL, ids) in memory behind one function, activated once, one-way, at module scope — before any component reads a token, not inside an effect, which would be too late for the first render.
3. Funnel every token/id accessor in your auth layer through **one** seam function (e.g. your `getCookie`) that checks "is demo active?" first and returns the in-memory demo value; only when demo is off does it fall through to the real `document.cookie` read.
4. Pick a fixture base URL that is guaranteed unroutable (an RFC 2606 reserved domain) so a demo request can never accidentally reach a real host if the backend interception is ever bypassed.
5. Pair this with a fake backend layer that intercepts requests addressed to that fixture URL and answers with fixture data, so nothing the demo does ever reaches the real network.

## Minimal example

```ts
export const DEMO_BASE_URL = "https://sandbox.example.invalid"   // RFC 2606 reserved — can never resolve
let active = false

export function activateDemoMode(): void { active = true }        // one-way; a page load is the only exit
export function demoModeActive(): boolean { return active }

function demoJar(): Record<string, string> {
  return { access_token: "demo.token", onehealth_base_url: DEMO_BASE_URL /* ...fixture ids... */ }
}

/** The ONE seam every token/id accessor funnels through. */
export function demoCookie(name: string): string | null | undefined {
  if (!active) return undefined        // "not my business" — caller reads the real cookie
  return demoJar()[name] ?? null       // "this cookie doesn't exist" — the real missing-cookie shape
}
```

## Gotchas

- **Never write demo tokens to real cookies** — a real session silently overwritten is a worse failure than any demo bug.
- **`undefined` vs `null` matters at the seam** — "demo is off, go read the real thing" and "demo is on but this cookie doesn't exist" are different answers, and callers rely on the distinction.
- **Make the fixture base URL structurally impossible to be a real host** (an RFC 2606 reserved domain), not just an unlikely-looking string.
- **One-way activation only** — a toggle that can flip back off after parts of the tree already read the demo value is a bug generator, not a feature.

## Related

- [environment-capability-detection.md](environment-capability-detection.md)
- Concepts: [setup/auth-and-launch.md](../setup/auth-and-launch.md)
