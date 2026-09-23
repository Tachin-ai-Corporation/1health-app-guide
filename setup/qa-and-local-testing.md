# QA & local testing: sign in as each role

A real launch comes from the 1health portal, which opens your app at its **registered launch URL**.
It can't launch a build on `localhost`, or any build that isn't at that URL. For those builds, your
app signs in as a **QA user** instead. The token route asks 1health for the same launch payload the
portal would have sent, minted with that QA user's API key, then runs the normal exchange. That's the
real flow with real permissions; only the portal's redirect is skipped. The exchange is
server-to-server, so it works from `localhost`.

> **⚠ Not yet in 1health's published API docs:** `GET /api/v2/external-application/{appId}/launch-payload`,
> the call that mints the payload. 1health supports it for **QA and development builds only**, never to
> sign real users in, and agents.1health.io has no page for it yet. The shape used here was verified
> against demo.

**The standard:**
- a demo **QA org** that stands in for your customer;
- one QA user and one API key per 1health role (**System Admin, Manager, Employee**);
- a **Sign in as <role> (QA)** button per role on `/auth`, in local and dev/stage builds only.

**An app is done when it passes QA as all three roles.**

## 1. Set up the QA org (once, in the 1health demo portal)

You do all of this in 1health's own portal, with no code and no API calls.

1. **Create a QA organization** in **demo** to stand in for your customer (e.g. "<Your app> QA").
   Put only test data in it, never real patient data.
2. **Add one QA user per role** (System Admin, Manager, Employee), each with only that role.
3. **Allow your app for the QA org** if your app is limited to specific organizations
   ([grant-app-access](../recipes/grant-app-access.md)).
4. **Create an API key for each QA user**, scoped to that user's role. Name the keys so they're easy
   to find and revoke later (e.g. `<app>-qa-manager`). Copy each key when it's shown, because a key's
   value can't be read back later.
5. **Put the three keys in `.env.local` yourself** (§2). The build agent reads them from there, the
   same way it gets the app's decrypt key. Don't paste them into code, chat, or a ticket.

> **If you're an AI agent:** the user does steps 1–5, because creating users and keys is theirs to do.
> Don't ask for keys in chat; ask the user to put them in `.env.local`. Then add the QA branch
> ([recipe](../recipes/qa-launch-with-api-key.md)) and sign in with the buttons.

## 2. Where QA keys may live: local and dev/stage only

QA keys are live credentials for your QA users. **They are never deployed with the production app.**

| Where | QA keys? |
|---|---|
| `.env.local` on your machine | ✅ The normal place. Next.js's default `.gitignore` keeps `.env*.local` out of git; confirm yours does. |
| A dev/stage deployment's env settings | ✅ Scope them to that deployment only, and set `APP_STAGE=dev` or `staging` there. Keep the deployment access-protected (host password/SSO, VPN, or an IP allowlist), because anyone who can open its `/auth` page can sign in as a QA user. |
| Your CI's secret store | ✅ Only for test jobs that run against a local or dev/stage build. |
| The production deployment | ❌ Never, not even temporarily. |
| The repo (`.env`, `.env.production`, example files, code, committed CI config) | ❌ Never. |
| Anything `NEXT_PUBLIC_*`, or client code | ❌ Never. `NEXT_PUBLIC_*` values are compiled into the browser bundle. |

```bash
# QA sign-in: .env.local, or a dev/stage deployment ONLY. Never production. Never committed.
ONEHEALTH_QA_KEY_SYSADMIN=...   # API key of the demo QA org's System Admin user
ONEHEALTH_QA_KEY_MANAGER=...    # API key of its Manager user
ONEHEALTH_QA_KEY_EMPLOYEE=...   # API key of its Employee user

# Deployed dev/stage builds only (`next dev` doesn't need it):
# APP_STAGE=staging             # "dev" or "staging" turns QA sign-in on for a deployed build
```

QA sign-in also needs your normal demo config, `APP_ID_DEMO` and `ONEHEALTH_SECRET_KEY_DEMO`
([scaffold.md](scaffold.md)), because the payload is decrypted with your app's own key.

The QA branch won't run unless the build is `next dev` or `APP_STAGE` is `dev`/`staging`. So a
production build stays closed even if a key reaches it by mistake. That check is only a backstop:
**keeping the keys off production is the actual control.** Revoke and re-create a QA key whenever it
may have been exposed, or when someone who had it leaves the project.

## 3. Sign in as a role

| | How | Use it for |
|---|---|---|
| **Primary: QA buttons on `/auth`** | Open the app with no launch payload, choose **Demo**, and click **Sign in as Manager (QA)**. The server mints the payload with that role's key and runs the normal exchange. | People, agents driving a browser, and Playwright. Tests can click the button, or skip the UI with `page.request.post(…/api/token, { data: { qaRole, environment: "demo" } })`. |
| **Fallback: mint outside the app** | A local script mints the payload with the role's key. It then either posts the payload to the app's normal `/api/token` exchange or prints a one-time `/auth?lpl=…` link for a person. | A build that doesn't have the QA branch yet. |

Code for both is in [recipes/qa-launch-with-api-key.md](../recipes/qa-launch-with-api-key.md). With the primary,
neither keys nor launch payloads reach the browser. The browser gets only the session cookies a
portal launch would set.

## 4. What to test: the QA checklist

Write a **role matrix** first: for each screen and action, what each role should be able to do.
The rows below are examples; yours come from what the app is for.

| Screen / action (example) | System Admin | Manager | Employee |
|---|---|---|---|
| View the patient list | allowed | allowed | allowed |
| Export all records | allowed | allowed | denied (button hidden) |
| Change org settings | allowed | denied | denied |

1health enforces permissions on the user's token regardless of the UI. Hiding a button is a
courtesy, not the control. Test every cell of the matrix, including the denied ones.

Then run through this **for each role**, starting from a fresh sign-in:

- [ ] **Signs in** and lands on the first screen as the right user in the QA org.
- [ ] **Every screen loads**, with no unexpected `401`/`403` and no console errors.
- [ ] **Allowed actions work end to end.** Re-read the record from 1health to confirm a write landed.
- [ ] **Denied actions fail cleanly:** hidden, or a clear message. Never a crash or a silent no-op.
- [ ] **Switching roles leaves nothing behind.** After signing in as another role in the same
  browser, no data, names, or cached lists from the previous role remain.

Once, with any role:

- [ ] **The session outlives the access token.** Leave the app idle past the token's lifetime; the
  next action should refresh silently instead of bouncing to `/auth`.

Before release, do one real launch from the 1health demo portal against a build at your app's
registered launch URL. It covers the one step QA sign-in skips: the portal's redirect into
`/auth?lpl=…`.

**Definition of done:**
- the checklist passes as **System Admin, Manager, and Employee** against demo;
- no QA key is set on the production deployment.

## 5. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Minting returns `403` `There are no permissions allowing the access to this endpoint: …/launch-payload` | That key's role isn't allowed to mint launch payloads. | Call [`GET /api/v2/token/context/api-access`](https://agents.1health.io/public/prod/api/v2/token/context/api-access/agents.md) with that key to list what it may call (this call can also return `403`). Ask your 1health admin to allow the launch-payload endpoint for that role. |
| Minting returns `401` | The key was revoked or has expired. Or demo is throttling: several calls in a few seconds with one key can get `401` for a few minutes. | Check the key; otherwise wait a few minutes. Don't retry in a loop, because retries extend the cooldown. |
| `/api/token` returns `400`: "decryption failed" | `ONEHEALTH_SECRET_KEY_DEMO` isn't this app's decrypt key (it's a placeholder or another app's key). | Set your app's real demo decrypt key. The payload is encrypted for the app id you minted it for. |
| `/api/token` returns `400` for a payload you already used | Payloads are single-use. | Mint a new one for every sign-in. |
| Signed in as the wrong person | Each key belongs to one user, and this one belongs to someone else. | Check which user owns each key. Use one QA user per role. |
| No QA buttons on `/auth` | QA sign-in is off (a deployed build without `APP_STAGE`), no QA keys are set, or you chose Production. | Choose Demo. Check `.env.local` or the deployment's settings, then restart `next dev`. |

## Related

- [recipes/qa-launch-with-api-key.md](../recipes/qa-launch-with-api-key.md): the QA branch, the `/auth` buttons, and the fallback script.
- [auth-and-launch.md](auth-and-launch.md): the launch exchange that QA sign-in reuses.
- [recipes/capability-probe.md](../recipes/capability-probe.md): expectation-based permission testing for a single credential.
- [anti-patterns.md](anti-patterns.md): sign-in shortcuts, admin-only QA, and QA keys in production.
