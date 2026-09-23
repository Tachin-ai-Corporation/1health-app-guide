# Register your app as a console application

> **Advanced / guardrailed pattern.**

**Use when:** your app is itself a developer console that needs to register (or connect to) a
1health "external application" record on the user's behalf — e.g. to hand back a launch URL and
secret for a project the user is building.
**Routes:** `GET/POST/PATCH /api/v2/external-application` (not yet in the published docs) · `PUT /api/v2/external-application/{id}` (not yet in the published docs) · `PUT /api/v2/external-application/{id}/state` (not yet in the published docs)

> **⚠ Not yet in 1health's published API docs:** `GET/POST/PATCH /api/v2/external-application`, `PUT /api/v2/external-application/{id}`, and `PUT /api/v2/external-application/{id}/state`. 1health supports them for third-party apps, but agents.1health.io has no page for them yet — the shapes shown here come from working apps. Test them against demo before you rely on them.

**Reference code:** [`app/api/console/application/route.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/app/api/console/application/route.ts#L155) · [`lib/api/console-application.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/api/console-application.ts) · [`lib/api/config.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/lib/api/config.ts#L265) (the lifecycle-state route shape — defined there, not yet exercised by that app)
**Seen in:** patient-vault

## Pattern

1. POST to create a new external-application record (multipart: name/url/description/icon),
   explicitly setting its visibility flags (e.g. non-public, not patient-facing) appropriate to a
   console-registered app rather than leaving them to default.
2. Capture the one-time `launchSecret` from the creation response **immediately** — like an API-key
   value, the platform returns it exactly once and never again.
3. Persist only a **masked/display form** of the secret for later display; never store or log the
   raw value beyond the single response that created it.
4. Support "connect an existing application by id" as a separate path (GET the record, adopt its
   id) for a user who registered one outside your console.
5. Keep your own record of which application belongs to which user/environment as a durable
   *pointer* (id, name, url, masked secret) — not a secrets store.
6. Move it through its lifecycle with the dedicated state endpoint — `Draft`/`Disabled` →
   `Pending` (request approval) → `Active`, or any state → `Disabled`/`Deprecated` — rather than
   inferring status from other fields on the record.
7. To rotate a secret, PUT the application record itself with a regenerate flag. The previous
   secret is invalidated **immediately**, so warn the user before firing it, not after.
8. If the reveal is human-facing, don't let it close on a backdrop click or Escape — require an
   explicit "I've stored it" acknowledgment before the close action even enables.

## Minimal example

```ts
async function registerConsoleApplication(form: FormData, userId: number, environment: "demo" | "production") {
  form.set("isPublic", "false")
  form.set("isAllowedForPatients", "false")

  const res = await authFetch(`${apiRootFor(environment)}/v2/external-application`, { method: "POST", body: form })
  if (!res.ok) throw new Error(`Failed to register application: ${res.status}`)
  const data = await res.json()

  if (typeof data.launchSecret !== "string" || !data.launchSecret) {
    // No recovery path — the secret is gone if this response is lost. Surface for manual follow-up.
    throw new Error("Application created, but its one-time key was not returned.")
  }

  await savePointer(userId, environment, {
    id: data.id,
    name: data.name,
    launchSecretMasked: data.launchSecretMasked,
  })
  return { applicationId: data.id, launchSecret: data.launchSecret } // show once, then discard
}

type AppState = "Draft" | "Pending" | "Active" | "Disabled" | "Deprecated"

async function setApplicationState(appId: number, environment: "demo" | "production", state: AppState) {
  const res = await authFetch(`${apiRootFor(environment)}/v2/external-application/${appId}/state`, {
    method: "PUT",
    body: JSON.stringify({ state }),
  })
  if (!res.ok) throw new Error(`Could not move application ${appId} to ${state}: ${res.status}`)
}

/** Invalidates the previous secret immediately — surface a confirm step before calling this. */
async function regenerateLaunchSecret(appId: number, environment: "demo" | "production") {
  const res = await authFetch(`${apiRootFor(environment)}/v2/external-application/${appId}`, {
    method: "PUT",
    body: JSON.stringify({ regenerateLaunchSecret: true }),
  })
  if (!res.ok) throw new Error(`Could not regenerate the secret: ${res.status}`)
  const { launchSecret } = await res.json()
  return launchSecret as string // one-time-visible again — same "show once" rule as creation
}
```

## Gotchas

- **If the create response omits `launchSecret`, that's an error state, not a warning** — there is
  no "reveal secret" endpoint to recover it later.
- **Visibility flags gate more than cosmetics.** `isPublic`/patient-facing settings control who can
  even see or launch the application — set them deliberately, not by omission.
- **Key your own bookkeeping by (user, environment), not just application id** — one registered
  application per user per environment (demo vs. production) is the common shape, and conflating
  environments points a user at the wrong platform deployment.
- **Regenerating invalidates the previous secret immediately** — any integration still using the
  old value breaks at that instant, not at its next scheduled use.
- **"Request approval" is only a legal move from `Draft` or `Disabled`** — gate the button by the
  record's current state; the backend enforces it too, but a confusing 400 is a worse UX than not
  offering the action.
- **A human-facing secret-reveal dialog should require an explicit acknowledgment before it can
  close** — a dismissible toast risks the secret being lost to a stray click or a navigation that
  races the copy action.

## Related

- [scoped-api-key-with-role.md](scoped-api-key-with-role.md) — the same one-time-secret shape.
- [tenant-provisioning.md](tenant-provisioning.md), [grant-app-access.md](grant-app-access.md)
- [split-identity-service-key.md](split-identity-service-key.md) — a registered console application is itself a privileged credential once launched.
