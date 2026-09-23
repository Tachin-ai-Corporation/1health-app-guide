# Authentication & the launch flow

1health apps authenticate with a **launch payload (LPL)** flow — conceptually like a SMART "EHR
launch": the 1health portal launches your app with an encrypted payload; your server decrypts it
once to obtain OAuth tokens; the browser then talks to the API directly with the user's token.

**This is the only place secrets are used, and the only server-side route in your app.**

## Provision your own app (do this first)

Every customer runs their **own** 1health app — **this guide and the template ship no credentials.**
Before the launch flow will work, you need, per environment:

- an **App ID** (`APP_ID_DEMO` / `APP_ID_PROD`), and
- an **app secret / decrypt key** (`ONEHEALTH_SECRET_KEY_DEMO` / `_PROD`) used to decrypt the launch payload.

You obtain these by **registering your application in 1health** (an admin/console task), then set them
as **server** environment variables — never `NEXT_PUBLIC_*`, never in the browser, never committed.
The user provisions these from their own 1health account and hands them to the build agent **separately**
(as env vars), not inside this guide. See [register-console-application.md](../recipes/register-console-application.md)
for registering an app programmatically, and 1health's
[auth quickstart](https://agents.1health.io/public/prod/api/authentication/agents.md) for credential acquisition.

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
to `/api/token`. **You'll normally build and test against demo** with your own demo login and your own app's demo credentials,
plus, for QA, the role keys of a demo QA org (see below).

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

## Local and dev/stage builds: sign in as a QA role

The portal launches your app only at its registered launch URL. It can't launch a build on
`localhost` or any other build that isn't at that URL. For those builds, add a **QA branch** to
`/api/token`:
- it asks 1health for the same launch payload the portal would have sent, minted with the API key
  of a QA user in your demo QA org (one key per role: System Admin, Manager, Employee);
- it then runs the exchange above, unchanged.

The exchange is server-to-server, so this works from `localhost`. The keys stay on the server and
never go on the production deployment, and the branch is off in production builds.
→ [qa-and-local-testing.md](qa-and-local-testing.md) (the QA standard and checklist),
[recipes/qa-launch-with-api-key.md](../recipes/qa-launch-with-api-key.md) (the code)

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

### Hardening

The refresh above is **proactive** (it checks expiry before sending). Harden it further:

- Make the on-`401` refresh **single-flight with queued retries** — if several calls `401` at once,
  they should share one refresh call and each retry off its result, not fire N concurrent refreshes
  against the same refresh token.
- Route calls that run before a session exists, or must never affect one, through a separate **bare**
  wrapper — no bearer, no `401`→refresh→logout handling at all. Turning credentials off per call on
  `authFetch` isn't the same thing: the shared `401` handler is still attached.

→ [recipes/resilient-api-client.md](../recipes/resilient-api-client.md)

## Rules

- **Never** call a 1health endpoint with raw `fetch` — you'll skip auth and refresh. Use `authFetch`.
- **Never** put `ONEHEALTH_SECRET_KEY_*` in client code or `NEXT_PUBLIC_*`. Server env only.
- **Never** set `ONEHEALTH_QA_KEY_*` on the production deployment, commit them, or expose them as
  `NEXT_PUBLIC_*`. QA keys belong only in `.env.local` and on dev/stage deployments.
- **Resolve the base URL per call** (`getOneHealthBaseUrl()`); it changes with the environment.
- Token refresh is direct browser → `POST {baseUrl}/auth/oauth2/token`
  (`grant_type=refresh_token`, `client_id=public-client`) — already handled for you.

Full write-up: template [`docs/AUTH-ARCHITECTURE.md`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/docs/AUTH-ARCHITECTURE.md).
Cold-start credential/token details: 1health's [auth quickstart](https://agents.1health.io/public/prod/api/authentication/agents.md).
