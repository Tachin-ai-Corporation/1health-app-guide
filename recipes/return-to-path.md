# Return-to path across a hosted-login bounce

> **Advanced / guardrailed pattern.**

**Use when:** you send the user to a 1health-hosted login/registration page and want to land them
back exactly where they were.
**Routes:** n/a — a small client utility.
**Reference code:** [patient-vault `lib/login-intent.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/login-intent.ts)
**Seen in:** patient-vault-official

## Pattern

1. Before redirecting to hosted login, save the current **relative** path to `sessionStorage`.
2. Validate it on the way in and out: it must be **same-origin** (relative) and not in a blocklist
   (`/auth`, `/api`, …).
3. After auth completes, **consume it once** and navigate there; clear it so a stale intent can't
   hijack a later navigation.

## Minimal example

```ts
const BLOCK = [/^\/auth/, /^\/api/]
export function saveLoginIntent(path: string) {
  if (path.startsWith("/") && !BLOCK.some((re) => re.test(path))) sessionStorage.setItem("intent", path)
}
export function consumeLoginIntent(): string | null {
  const p = sessionStorage.getItem("intent"); sessionStorage.removeItem("intent")
  return p && p.startsWith("/") ? p : null
}
```

## Gotchas

- **Open-redirect guard:** store and honor **relative** paths only — never an absolute URL a caller
  could point off-origin.
- Consume-once, or a saved intent silently redirects a later, unrelated login.

## Related

- [setup/auth-and-launch.md](../setup/auth-and-launch.md) · [auth-url-branding.md](auth-url-branding.md)
