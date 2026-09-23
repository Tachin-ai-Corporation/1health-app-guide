# Brand the hosted login / registration pages

> **Advanced / guardrailed pattern.**

**Use when:** you route users to 1health-hosted `/login` or `/register` and want your app's branding
(logo/colors) and light/dark mode on those pages.
**Routes:** n/a for consuming `brandingId` (it just decorates the hosted URL) · behind the scenes:
`GET /api/v3/public/ui-customization/config` → [agents.md](https://agents.1health.io/public/prod/api/v3/public/ui-customization/config/agents.md) (public read, by guid) · `POST /api/graphql` → [agents.md](https://agents.1health.io/public/prod/api/graphql/agents.md) (authoring)
**Reference code:** [patient-vault `lib/auth-branding.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/auth-branding.ts)
**Seen in:** patient-vault-official

## Pattern

1. A **`brandingId`** (a GUID minted out-of-band in the 1health admin console, **per app and per
   environment**) selects the hosted-page theme.
2. Pick the right `brandingId` by destination hostname, then append it — plus `mode` (light/dark)
   and any referral flag — as query params on the outbound hosted URL.
3. If you ever need to **read** that config yourself (not just hand the guid to 1health), it's a
   public, unauthenticated `GET` by guid — call it through a bare, interceptor-free client (see
   [resilient-api-client.md](resilient-api-client.md)) with a short timeout, and fail open to your
   own defaults on **any** outcome other than "found and enabled" (missing guid, 404, a disabled
   flag, a timeout). A visitor on the login page isn't signed in yet — there's no authenticated
   fallback to reach for.
4. **Author** the record (colors/copy/logo, an enabled flag, a default mode) via authenticated
   GraphQL create/update/delete, gated to whoever manages your app's settings. Its configuration
   payload is a free-form JSON blob you define the shape of yourself — treat it like `customData`,
   not a fixed platform schema.

## Minimal example

```ts
const BRANDING = { demo: process.env.NEXT_PUBLIC_BRANDING_DEMO!, prod: process.env.NEXT_PUBLIC_BRANDING_PROD! }
export function withBranding(url: string, env: "demo" | "prod", mode: "light" | "dark") {
  const u = new URL(url)
  u.searchParams.set("brandingId", BRANDING[env])
  u.searchParams.set("mode", mode)
  return u.toString()
}
```

## Gotchas

- `brandingId` values are **tenant/environment-specific** — pull them from config per environment,
  never hardcode one across envs (an anti-pattern — see [anti-patterns.md](../setup/anti-patterns.md)).
- This themes only the **hosted** 1health pages; your own app UI is branded via the design system.
- **Fail open, always.** A slow or broken branding fetch should degrade silently to your hardcoded
  defaults, never block or blank the login/registration page itself.

## Related

- [survive-an-auth-redirect.md](survive-an-auth-redirect.md) — carrying `brandingId`/`mode` across
  the hosted-login hop.
- [resilient-api-client.md](resilient-api-client.md) — the bare client the branding read should use.
- [setup/auth-and-launch.md](../setup/auth-and-launch.md) · [return-to-path.md](return-to-path.md)
