# Authentication & the launch flow

1health apps authenticate with a **launch payload (LPL)** flow — conceptually like a SMART "EHR
launch": the 1health portal launches your app with an encrypted payload; your server decrypts it
once to obtain OAuth tokens; the browser then talks to the API directly with the user's token.

**This is the only place secrets are used, and the only server-side route in your app.**

## The flow

```
┌───────────┐    ┌──────────┐    ┌───────────────┐    ┌────────────┐
│ 1health   │    │ Browser  │    │ App Server    │    │ 1health API│
│ Portal    │    │          │    │ (/api/token)  │    │            │
└─────┬─────┘    └────┬─────┘    └───────┬───────┘    └─────┬──────┘
      │ 1. launch w/   │                  │                  │
      │  encrypted LPL │                  │                  │
      │───────────────>│                  │                  │
      │                │ 2. POST /api/token{ lpl }           │
      │                │─────────────────>│                  │
      │                │                  │ 3. decrypt LPL   │
      │                │                  │   with env secret│
      │                │                  │ 4. exchange code │
      │                │                  │─────────────────>│
      │                │                  │ 5. OAuth tokens  │
      │                │                  │<─────────────────│
      │                │ 6. set cookies   │                  │
      │                │<─────────────────│                  │
      │                │ 7. direct API calls with Bearer token (authFetch)
      │                │────────────────────────────────────>│
```

Steps 1–6 happen once, at launch. Step 7 is your entire app from then on.

## Environments

Two environments, each with its own secret key and base URL:

| Environment | Secret key (env var) | Base URL |
|---|---|---|
| Demo | `ONEHEALTH_SECRET_KEY_DEMO` | `https://demo.1health.io` |
| Production | `ONEHEALTH_SECRET_KEY_PROD` | `https://app.1health.io` |

The environment is auto-detected from `document.referrer` (a `demo.1health` referrer → demo, an
`app.1health` referrer → prod), otherwise the user picks. It is persisted in a cookie and passed
to `/api/token`. **You'll normally build and test against demo** with the demo credentials you were given.

## The one server route: `/api/token`

`POST /api/token` receives `{ lpl, environment }`, then:
1. Selects the env-specific secret key.
2. Decrypts the LPL — **AES-256-GCM**, with a key derived from the payload via **HKDF-SHA256**
   (the payload is `IV(12 bytes) + ciphertext + authTag(16 bytes)`, base64-encoded).
3. Reads the decrypted claims (`apiKey`, `tenant.id`, `user.id`, a one-time code, plus optional
   context like `provider_npi`, `journey_id`, `encounter_id`).
4. Exchanges the one-time code for OAuth tokens at the 1health auth server.
5. Sets cookies (below) and returns.

You get this route working out of the box from the app template — copy it as-is. Reference:
[`app/api/token/route.tsx`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/app/api/token/route.tsx).
**Do not** reimplement the crypto by hand; the derivation must byte-match the platform's.

## Cookies the flow sets

| Cookie | Purpose |
|---|---|
| `access_token` | Bearer token for API calls (~50 min) |
| `refresh_token` | Refresh the access token (~7 days) |
| `token_expires_at` | Unix seconds; drives proactive refresh |
| `onehealth_base_url` | API base URL for this environment — resolve **per call** |
| `onehealth_environment` | `demo` or `prod` |
| `user_id`, `user_org_id` | Current user & org ids |

Tokens are intentionally **not** `httpOnly` — the browser needs them for client-side calls.

## `authFetch` — the only way you call the API

Every client call goes through `authFetch` (from `lib/auth-client.ts`). It attaches the Bearer
token, proactively refreshes when the token is close to expiry, transparently retries once on a
`401`, and throws `SessionExpiredError` when refresh fails.

```ts
import { authFetch, getOneHealthBaseUrl } from "@/lib/auth-client"

const baseUrl = getOneHealthBaseUrl()               // resolve per call — never cache it
const res = await authFetch(`${baseUrl}/api/v2/query`, {
  method: "POST",
  body: JSON.stringify({ key: "Person", attributes: ["id", "firstName"], limit: 1 }),
})
if (!res.ok) throw new Error(`query failed: ${res.status}`)
const data = await res.json()
```

Most modules wrap this once more in a `callApi` helper that returns a uniform
`ApiResponse<T> = { success, data?, error?, statusCode? }` envelope — see
[recipes/query-the-data-graph.md](../recipes/query-the-data-graph.md) and the template's
[`lib/api/client.ts`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/lib/api/client.ts).

## Rules

- **Never** call a 1health endpoint with raw `fetch` — you'll skip auth and refresh. Use `authFetch`.
- **Never** put `ONEHEALTH_SECRET_KEY_*` in client code or `NEXT_PUBLIC_*`. Server env only.
- **Resolve the base URL per call** (`getOneHealthBaseUrl()`); it changes with the environment.
- Token refresh is direct browser → `POST {baseUrl}/auth/oauth2/token`
  (`grant_type=refresh_token`, `client_id=public-client`) — already handled for you.

Full write-up: template [`docs/AUTH-ARCHITECTURE.md`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/docs/AUTH-ARCHITECTURE.md).
Cold-start credential/token details: 1health's [auth quickstart](https://agents.1health.io/public/prod/api/authentication/agents.md).
