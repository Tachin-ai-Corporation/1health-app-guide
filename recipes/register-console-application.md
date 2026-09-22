# Register your app as a console application

> **Advanced / guardrailed pattern.**

**Use when:** your app is itself a developer console that needs to register (or connect to) a
1health "external application" record on the user's behalf — e.g. to hand back a launch URL and
secret for a project the user is building.
**Routes:** `GET/POST/PATCH /api/v2/external-application` → [route docs](https://agents.1health.io/public/prod/api/manifest.md) · `/{id}` variant → [route docs](https://agents.1health.io/public/prod/api/manifest.md)
**Reference code:** [`app/api/console/application/route.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/app/api/console/application/route.ts#L155) · [`lib/api/console-application.ts`](https://github.com/Tachin-ai-Corporation/patient-vault-official/blob/main/lib/api/console-application.ts)
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
```

## Gotchas

- **If the create response omits `launchSecret`, that's an error state, not a warning** — there is
  no "reveal secret" endpoint to recover it later.
- **Visibility flags gate more than cosmetics.** `isPublic`/patient-facing settings control who can
  even see or launch the application — set them deliberately, not by omission.
- **Key your own bookkeeping by (user, environment), not just application id** — one registered
  application per user per environment (demo vs. production) is the common shape, and conflating
  environments points a user at the wrong platform deployment.

## Related

- [scoped-api-key-with-role.md](scoped-api-key-with-role.md) — the same one-time-secret shape.
- [tenant-provisioning.md](tenant-provisioning.md), [grant-app-access.md](grant-app-access.md)
- [split-identity-service-key.md](split-identity-service-key.md) — a registered console application is itself a privileged credential once launched.
