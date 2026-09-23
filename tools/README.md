# Maintainer tools

Checks to run before publishing changes to this guide. Both need network access to
agents.1health.io and run in PowerShell 5.1+ or PowerShell 7 (`pwsh`, cross-platform).

| Script | What it checks |
|---|---|
| `audit-routes.ps1` | Every `METHOD /api/...` route cited in the guide is documented in 1health's public API docs — in the manifest, or as a `## METHOD /path` heading on its collection's page (the manifest folds many item routes like `/{id}` into their collection page). |
| `check-doc-links.ps1` | Every agents.1health.io link lands on a page that actually documents a route — not a 404, and not a child-route index. |

```bash
pwsh -File tools/audit-routes.ps1 -Out route-audit.md
pwsh -File tools/check-doc-links.ps1
```

A route reported as missing is acceptable only if 1health supports it for third-party apps but
hasn't documented it yet — and then the recipe that teaches it must carry the
`⚠ Not yet in 1health's published API docs` banner.
