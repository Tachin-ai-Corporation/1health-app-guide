# 1health App Guide

**A guide, written for LLMs, for turning a disconnected front-end prototype into a working,
1health-compliant application** — where 1health is the *only* backend.

Point a harnessed LLM (Claude Code, Cursor, etc.) at this repo and it can build a real 1health
app from a prototype + demo credentials + an app secret.

## The entry point

Everything starts at **[`llms.txt`](llms.txt)** — the single index an agent reads first.

```bash
# Drop this URL to any LLM (works once published):
curl https://raw.githubusercontent.com/Tachin-ai-Corporation/1health-app-guide/main/llms.txt
```

Or `git clone` this repo so the LLM can grep the whole tree locally (the recommended mode).

## How it's organized

| Layer | Folder | What it is |
|---|---|---|
| **Setup** (the *what*) | [`setup/`](setup/) | The rules, the launch/auth flow, scaffolding, and the prototype→app playbook. |
| **Recipes** (the *how*) | [`recipes/`](recipes/) | Abstract, reusable patterns. Start at [`recipes/INDEX.md`](recipes/INDEX.md). |
| **API** (the *tactical*) | [`api/`](api/) | A bridge to the live per-route docs at `agents.1health.io` (not duplicated here). |

## Sources it's distilled from

- **Reference app / template:** [`v0-1h-app-template`](https://github.com/Tachin-ai-Corporation/v0-1h-app-template) — the canonical setup and typed API layer.
- **Live API docs:** [`agents.1health.io`](https://agents.1health.io/public/prod/llms.txt) — auto-generated, 474 routes.
- **Example apps** (mined for recipes): expertdx-ordering-provider, v0-trc-care-coordinator,
  pcp-transitional-care-management, med-adherence-bcbsm, v0-1h-query-helper, secure-share,
  patient-vault-official.

## Status

🚧 **Draft — recipe library complete.** Setup docs + a ~90-recipe library across 13 categories,
distilled from seven production apps and the template, are written and cross-linked. See
[`recipes/INDEX.md`](recipes/INDEX.md). Next: end-to-end validation with a fresh LLM + a throwaway
prototype. Not yet published publicly.

## Build phases

1. **Phase 0/1** ✅ — scaffold + port the template into setup + sample recipes.
2. **Phase 2** ✅ — mine all 7 example apps → a Pattern Catalog per repo → reviewed at Gate 2.
3. **Phase 3** ✅ — write the approved recipes; weave the index, conventions & anti-patterns.
4. **Phase 4** — validate with a fresh LLM + a throwaway prototype; then publish.
