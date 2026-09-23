# Playbook: disconnected prototype → 1health app

This is the meta-recipe. You have a front-end prototype (screens + mock data) and demo
credentials. Follow these phases in order. Each links to the recipe that does the heavy lifting.

## Phase A — Inventory the prototype (no code yet)

Produce two lists by reading the prototype:

1. **Entities** — the nouns the UI shows (patients, orders, providers, cases, tasks, documents…).
   For each: its fields, and whether it looks like a *record* (a thing) or a *process* (a
   multi-step flow with status).
2. **Actions** — the verbs (search, create, assign, upload, comment, submit, share, export…).

Write these down; they drive every later mapping.

## Phase B — Map entities to the 1health graph

For each entity, decide what it is on the platform:

- **An existing data-object type?** Discover the schema — list types, then inspect the closest
  type's attributes. → *Recipe: schema discovery* (Phase 3). Prefer real types for anything you
  need to **filter or sort on**.
- **App-specific fields on an existing type?** Put them in `customData` under `appData.<appId>`.
  → [read-write-custom-data.md](../recipes/read-write-custom-data.md)
- **A process/workflow?** Model it as a Campaign → Journey → Steps. → *Recipe: workflows* (Phase 3).

Record the mapping (prototype entity → 1health type + which fields are attributes vs customData).
When in doubt: **filterable/sortable → schema attribute; everything else → customData.**

## Phase C — Stand up auth

Get the template signing in against demo before wiring any screen. Locally, that means using the
QA sign-in branch:
1. The user sets up a demo QA org with one key per role.
2. You click **Sign in as System Admin (QA)** on `/auth`.

If auth works, the base URL and token cookies are set and every recipe "just works."
→ [auth-and-launch.md](auth-and-launch.md), [scaffold.md](scaffold.md), [qa-and-local-testing.md](qa-and-local-testing.md)

## Phase D — Replace mock data, screen by screen

For each screen, in dependency order (read-only lists first, then detail, then writes):

1. Find the mock source behind the screen.
2. Pick the read engine: a **list/table** → grid endpoint; an **entity + its relations** →
   `/api/v2/query`. → [query-the-data-graph.md](../recipes/query-the-data-graph.md)
3. Replace the mock call with a typed `lib/api/*` function, fetched via **SWR**.
4. Map response fields to the prototype's props (mind the `ROOT.<Type>.<attr>` prefixes).
5. For writes: schema attribute → the type's update path; app field → `customData`; a workflow
   step → submit the step (never invent a "save" endpoint).

**Confirm every payload shape in the live per-route docs before coding it.** → [api/README.md](../api/README.md)

## Phase E — Cross-cutting features

Wire these where the prototype uses them (each is a Phase-3 recipe): files/attachments,
comments, assignment, sharing with partner orgs, notifications/webhooks, export, reference-data
lookups (NPI, ICD-10). Find them in the [Recipe Index](../recipes/INDEX.md).

## Phase F — Self-provisioning (if it uses a workflow)

So the app works on a fresh tenant, have it **find-or-clone** its workflow template and create +
activate its campaign by name on first run, instead of assuming they exist.
→ *Recipe: provisioning* (Phase 3).

## Phase G — QA as every role

Run the QA checklist as **System Admin, Manager, and Employee**:
1. Write the role matrix first.
2. Test both the allowed and the denied cells.

A pass as admin alone hides every permission bug. → [qa-and-local-testing.md](qa-and-local-testing.md)

## Phase H — Validate against the definition of done

- [ ] No backend but 1health; only `/api/token` is server-side.
- [ ] Every read/write goes through `authFetch` (no raw `fetch`, base URL resolved per call).
- [ ] No hardcoded step-field GUIDs (resolved by `label`).
- [ ] App data namespaced under `appData.<appId>`; nested writes use the safe merge.
- [ ] Runs end-to-end on demo with the provided credentials.
- [ ] Passes the QA checklist as System Admin, Manager, and Employee on demo.
- [ ] No QA key on the production deployment; the QA branch is off there.

## Anti-patterns (stop if you catch yourself doing these)

- Adding a database or any non-1health persistence "just for this one thing."
- Building a server route per feature — you need exactly one (`/api/token`); rare CORS/secret
  proxies aside.
- Hardcoding ids/GUIDs that differ across environments.
- Deep-merging into `customData` with a raw APPEND (it shallow-replaces the subtree).
- A sign-in shortcut that skips the launch exchange (a mock session, a pasted token), or testing
  only as an admin.
