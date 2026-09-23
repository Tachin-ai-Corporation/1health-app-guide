# Sign in as a QA role with an API key (local and dev/stage builds)

**Use when:** you need to sign a local (`localhost`) or dev/stage build in as a System Admin, a
Manager, or an Employee to test it. The 1health portal only launches your app at its registered
launch URL.
**Routes:**
- `GET /api/v2/external-application/{appId}/launch-payload` (not yet in the published docs);
- the normal exchange, `POST /api/v2/public/external-application/auth/oauth2/user/token` → [agents.md](https://agents.1health.io/public/prod/api/v2/public/external-application/auth/oauth2/user/token/agents.md);
- for troubleshooting, `GET /api/v2/token/context/api-access` → [agents.md](https://agents.1health.io/public/prod/api/v2/token/context/api-access/agents.md).

> **⚠ Not yet in 1health's published API docs:** `GET /api/v2/external-application/{appId}/launch-payload`.
> 1health supports it for **QA and development builds only**, never to sign real users in, and
> agents.1health.io has no page for it yet. The shape shown here was verified against demo; test it
> there before you rely on it.

**Reference code:** the template's [`app/api/token/route.tsx`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template/blob/main/app/api/token/route.tsx), whose exchange this reuses unchanged. The QA branch itself isn't in the template yet; it's the Minimal example below.
**Seen in:** 1health's QA standard, verified end to end on demo (mint → exchange → session) with a template-based app.

## Pattern

1. **Put the QA branch inside `/api/token`**, so there's no new server route. It runs only when
   both of these hold:
   - the build is `next dev`, or a deployment explicitly marked `APP_STAGE=dev|staging`;
   - that role's key (`ONEHEALTH_QA_KEY_<ROLE>`) is set.

   Otherwise it answers `404`.
2. **`GET /api/token` returns `{ qaRoles }`**, the roles this build can sign in as (`[]` when QA
   sign-in is off). `/auth` uses it to decide which buttons to draw.
3. **`POST /api/token { qaRole }`**: the server calls
   `GET /api/v2/external-application/{APP_ID_DEMO}/launch-payload` on demo with that role's key.
   1health answers `{ "launchPayload": "…" }`. That's the same encrypted payload the portal would
   have put in `?lpl=`, minted for the user who owns the key.
4. **Run the unchanged exchange on it:**
   - decrypt it with `ONEHEALTH_SECRET_KEY_DEMO`;
   - sign the one-time code and exchange it;
   - set the session cookies.

   The exchange is server-to-server, so it works from `localhost`.
5. **On `/auth`**, when there's no launch payload and the environment is demo, draw one
   **Sign in as <Role> (QA)** button per role. After a QA sign-in, do a full page load into the app.

The key and the payload never reach the browser, which gets only the session cookies a portal
launch would set. The session is a real one for the QA user, with that user's identity, org, and
permissions.

## Primary vs fallback

- **Primary: QA buttons on `/auth` (this recipe).** Keys and payloads stay on the server, it takes
  one click per role, and it runs the real exchange with the role's real permissions. People click
  the buttons, and so do agents driving a browser and Playwright tests. A test can also skip the UI
  with `page.request.post(appUrl + "/api/token", { data: { qaRole: "manager", environment: "demo" } })`,
  which stores the session cookies in the test browser.
- **Fallback: mint outside the app.** A local script mints the payload with the role's key. It then
  either posts the payload to the app's normal `/api/token` exchange (`{ lpl, environment: "demo" }`)
  or prints a one-time `/auth?lpl=…` link for a person. Switch to it only for a build that doesn't
  have the QA branch.

## Minimal example

Server: these are additions to the template's token route. The rest of the route stays as the
template ships it.

```ts
// app/api/token/route.tsx

// Next.js 14 treats a GET handler that never reads the request as static, run once at build time.
export const dynamic = "force-dynamic"

const QA_ROLES = ["sysadmin", "manager", "employee"] as const
type QaRole = (typeof QA_ROLES)[number]

/** QA sign-in is on for `next dev`, or a deployment explicitly marked dev/staging. Unset means off. */
function qaSignInEnabled(): boolean {
  const stage = process.env.APP_STAGE
  return process.env.NODE_ENV === "development" || stage === "dev" || stage === "staging"
}

/** The role's QA key, only when QA sign-in is on and that key is set. */
function qaKey(role: unknown): string | undefined {
  if (!qaSignInEnabled() || !QA_ROLES.includes(role as QaRole)) return undefined
  return process.env[`ONEHEALTH_QA_KEY_${(role as QaRole).toUpperCase()}`] || undefined
}

/** GET /api/token → the QA roles this build can sign in as ([] when QA sign-in is off). */
export async function GET() {
  return NextResponse.json({ qaRoles: QA_ROLES.filter((role) => qaKey(role)) })
}

/** The launch payload the portal would have sent, minted for the QA user who owns `key`. */
async function mintQaLaunchPayload(key: string): Promise<string> {
  const appId = process.env.APP_ID_DEMO
  if (!appId) throw new Error("APP_ID_DEMO is not set")
  const res = await fetch(
    `https://demo.1health.io/api/v2/external-application/${encodeURIComponent(appId)}/launch-payload`,
    { headers: { Accept: "application/json", Authorization: `Bearer ${key}` }, cache: "no-store" },
  )
  if (!res.ok) throw new Error(`1health refused the QA launch payload (${res.status})`)
  const { launchPayload } = await res.json()
  if (typeof launchPayload !== "string" || !launchPayload) throw new Error("1health returned no launch payload")
  return launchPayload
}

export async function POST(req: Request) {
  const body = await req.json()
  let environment: Environment = body.environment === "prod" ? "prod" : "demo"
  let lpl: string | undefined = typeof body.lpl === "string" && body.lpl ? body.lpl : undefined

  if (!lpl && body.qaRole !== undefined) {
    const key = qaKey(body.qaRole)
    if (!key) return NextResponse.json({ error: "Not found" }, { status: 404 })
    environment = "demo" // QA always runs against demo
    try {
      lpl = await mintQaLaunchPayload(key)
    } catch (err) {
      return NextResponse.json({ error: (err as Error).message }, { status: 502 })
    }
  }

  // ...the rest of the template's route is unchanged: decrypt `lpl` with the environment's
  // ONEHEALTH_SECRET_KEY_*, sign the one-time code, exchange it, and set the session cookies.
}
```

`/auth`: add a QA panel to the screen shown when there's no launch payload.

```tsx
// app/auth/page.tsx
const QA_LABELS: Record<string, string> = { sysadmin: "System Admin", manager: "Manager", employee: "Employee" }

const [qaRoles, setQaRoles] = useState<string[]>([])
useEffect(() => {
  fetch("/api/token", { cache: "no-store" })
    .then((res) => (res.ok ? res.json() : { qaRoles: [] }))
    .then((data) => setQaRoles(Array.isArray(data.qaRoles) ? data.qaRoles : []))
    .catch(() => setQaRoles([]))
}, [])

async function qaSignIn(qaRole: string) {
  const res = await fetch("/api/token", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ qaRole, environment: "demo" }),
  })
  if (!res.ok) {
    const data = await res.json().catch(() => ({}))
    showError(data.error ?? `QA sign-in failed (${res.status})`) // however the page shows a failed launch
    return
  }
  window.location.assign("/") // a full load, so nothing cached for a previous role survives
}

// in the JSX of the "no launch payload" screen:
{environment === "demo" && qaRoles.length > 0 && (
  <div className="flex flex-col gap-2 rounded-md border border-dashed p-3">
    <p className="text-xs text-muted-foreground">QA sign-in: local and dev/stage builds only</p>
    {qaRoles.map((role) => (
      <Button key={role} variant="secondary" onClick={() => void qaSignIn(role)}>
        Sign in as {QA_LABELS[role] ?? role} (QA)
      </Button>
    ))}
  </div>
)}
```

Fallback, for a build without the QA branch. This runs in Node (a test setup or a local script)
with `.env.local` loaded, never in the browser.

```ts
async function mintQaPayloadLocally(role: "sysadmin" | "manager" | "employee"): Promise<string> {
  const key = process.env[`ONEHEALTH_QA_KEY_${role.toUpperCase()}`]
  const appId = process.env.APP_ID_DEMO
  if (!key || !appId) throw new Error(`Set APP_ID_DEMO and ONEHEALTH_QA_KEY_${role.toUpperCase()} in .env.local`)
  const res = await fetch(
    `https://demo.1health.io/api/v2/external-application/${encodeURIComponent(appId)}/launch-payload`,
    { headers: { Accept: "application/json", Authorization: `Bearer ${key}` } },
  )
  if (!res.ok) throw new Error(`launch-payload refused (${res.status})`)
  return (await res.json()).launchPayload
}

// Playwright: run the same exchange /auth performs. The session cookies land in the test browser.
const lpl = await mintQaPayloadLocally("employee")
await page.request.post(`${appUrl}/api/token`, { data: { lpl, environment: "demo" } })
await page.goto(appUrl)

// Or, for a person: print a one-time link. Open it right away (choose Demo if asked); don't share or save it.
console.log(`${appUrl}/auth?lpl=${encodeURIComponent(await mintQaPayloadLocally("manager"))}`)
```

## Gotchas

- **Never on production.** QA keys live only in `.env.local` or a dev/stage deployment
  ([setup/qa-and-local-testing.md](../setup/qa-and-local-testing.md) §2). The branch also won't
  run unless the build is `next dev` or `APP_STAGE` is `dev`/`staging`; unset means off. So a
  production build stays closed even if a key reaches it by mistake. If your host gives the app a
  production signal that isn't copied along with env vars (Vercel sets `VERCEL_ENV=production`),
  refuse on that too.
- **Keys and payloads stay on the server.** Never return a payload to the browser, put it in a URL,
  or log it. The same goes for the key and the session cookies, because test logs persist. The
  fallback's printed link is the one deliberate exception: it's for a person, on their own machine.
- **A payload works once.** Exchanging the same payload again fails with a `400`. Mint a fresh one
  for each sign-in, and exchange it right away.
- **It's the QA user's real session**, with their identity, org, and permissions. Give each QA user
  only the role it stands for, or the session picks up the other role's permissions too.
- **Demo only.** The branch forces `environment = "demo"`. QA users and keys live in the demo QA
  org, never in production.
- **Keep `dynamic = "force-dynamic"`.** Next.js 14 treats a `GET` handler that never reads the
  request as static and runs it once at build time. Without the export, the role list is frozen
  into the build.
- **Do a full page load after a QA sign-in.** A client-side route push can keep data or session
  context cached from the previous role.
- **`403` `There are no permissions allowing the access to this endpoint: …/launch-payload`** means
  that key's role isn't allowed to mint. `GET /api/v2/token/context/api-access`, called with the key
  itself, lists what the key may call: roles → functionalities → `{ method, url }` endpoints. For
  fixes, see the troubleshooting table in the setup doc.
- **Demo throttles bursts.** Several calls in a few seconds with one key can be answered with `401`
  for minutes, and retrying extends the wait. Wait it out instead of retrying in a loop.

## Related

- [setup/qa-and-local-testing.md](../setup/qa-and-local-testing.md): the QA org, where keys may live, the checklist, and troubleshooting.
- [setup/auth-and-launch.md](../setup/auth-and-launch.md): the exchange this reuses.
- [enrich-session-in-token-route.md](enrich-session-in-token-route.md): the same move of staying at one server route.
- [capability-probe.md](capability-probe.md): expectation-based permission testing for a single credential.
- [grant-app-access.md](grant-app-access.md): allow the QA org to use your app.
- [demo-mode-seam.md](demo-mode-seam.md): the opposite need, a demo on invented data with no 1health behind it.
