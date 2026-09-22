# Brand the hosted login / registration pages

> **Advanced / guardrailed pattern.**

**Use when:** you route users to 1health-hosted `/login` or `/register` and want your app's branding
(logo/colors) and light/dark mode on those pages.
**Routes:** n/a — decorates the hosted URLs with query params.
**Reference code:** [patient-vault `lib/auth-branding.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/auth-branding.ts)
**Seen in:** patient-vault-official

## Pattern

1. A **`brandingId`** (a GUID minted out-of-band in the 1health admin console, **per app and per
   environment**) selects the hosted-page theme.
2. Pick the right `brandingId` by destination hostname, then append it — plus `mode` (light/dark)
   and any referral flag — as query params on the outbound hosted URL.

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

## Related

- [setup/auth-and-launch.md](../setup/auth-and-launch.md) · [return-to-path.md](return-to-path.md)
