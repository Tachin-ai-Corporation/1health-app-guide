# 1health App Guide

**A guide, written for LLMs, for turning a disconnected front-end prototype into a working,
1health-compliant application** — where 1health is the *only* backend.

Point a harnessed LLM (Claude Code, Cursor, etc.) at this repo and it can build a real 1health
app from a prototype + demo credentials + an app secret.

## The entry point

Everything starts at **[`llms.txt`](llms.txt)** — the single index an agent reads first.

```bash
# Drop this URL to any LLM:
curl https://raw.githubusercontent.com/Tachin-ai-Corporation/1health-app-guide/main/llms.txt
```

Or `git clone` this repo so the LLM can grep the whole tree locally (the recommended mode).

## How it's organized

| Layer | Folder | What it is |
|---|---|---|
| **Setup** (the *what*) | [`setup/`](setup/) | The rules, the launch/auth flow, scaffolding, the prototype→app playbook, and QA as each role. |
| **Recipes** (the *how*) | [`recipes/`](recipes/) | Abstract, reusable patterns. Start at [`recipes/INDEX.md`](recipes/INDEX.md). |
| **API** (the *tactical*) | [`api/`](api/) | A bridge to the live per-route docs at `agents.1health.io` (not duplicated here). |

## Sources it's distilled from

- **Reference app / template:** [`v0-1h-app-template`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template) — the canonical setup and typed API layer.
- **Live API docs:** [`agents.1health.io`](https://agents.1health.io/public/prod/llms.txt) — auto-generated, 474 routes.
- **Example apps** (mined for recipes): expertdx-ordering-provider, v0-trc-care-coordinator,
  pcp-transitional-care-management, med-adherence-bcbsm, v0-1h-query-helper, secure-share,
  patient-vault-official.
- **1health platform usage** — how 1health's own product uses its API, abstracted into patterns
  (no code) and checked against the published docs.
- **Live checks on demo** — request shapes, sentinels, operators, and lifecycles exercised against
  the demo environment; each recipe says what was verified.

## Status

**Published — `guide_version` 0.5.0 (draft).** Setup docs plus ~125 recipes across 14 categories,
including:
- a QA standard: sign in as each role on local and dev/stage builds;
- a population-health section: the command center, covering cohorts, snapshots, and
  cohort-launched campaigns.

Key behaviors are verified against the demo environment. See
[`recipes/INDEX.md`](recipes/INDEX.md).

**Next:** end-to-end validation with a fresh LLM and a throwaway prototype.

## Build phases

1. **Phase 0/1** ✅ — scaffold + port the template into setup + sample recipes.
2. **Phase 2** ✅ — mine all 7 example apps → a Pattern Catalog per repo → reviewed at Gate 2.
3. **Phase 3** ✅ — write the approved recipes; weave the index, conventions & anti-patterns.
4. **Publish** ✅ — public repo; `llms.txt` served from raw GitHub.
5. **Phase 5: platform patterns** ✅ — abstract how 1health's own product uses its API into
   recipes, with primary-vs-fallback guidance, and verify key behaviors live on demo.
6. **Phase 6: QA standard** ✅ — a demo QA org with one key per role, and QA sign-in for local and
   dev/stage builds.
7. **Population health** ✅ — the command center (cohorts → snapshots → campaigns), verified end to
   end on demo.
8. **Phase 4: validation** — have a fresh LLM build from a throwaway prototype, then fold the fixes
   back in.
