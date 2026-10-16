# Contributing to the 1health App Guide

This guide is **public**. Everything in it can be read, copied, and fed to any LLM. These rules are
canon: every change — by a person or an agent, including content pasted in from elsewhere — must
follow them before it's merged.

## 1. Abstract everything; nothing private

Many of the apps this guide learned from are private. The guide keeps the **patterns** and drops
everything that identifies or reproduces those apps.

- **Never link to a private repo.** `Reference code` may point only at a public repo — normally the
  [app template](https://github.com/Tachin-ai-Corporation/v0-1h-app-template). With no public
  reference, write exactly: `**Reference code:** none public — see the Minimal example.`
- **Never name a private app or repo.** In `Seen in`, describe the kind of app generically
  (“a care-coordination app”, “a secure file-sharing app”). Name only public repos.
- **Never cite private internals:** file paths, function, constant or type names, ticket ids,
  internal hostnames, or the vendors, customers and payers a private app works with.
- **Never copy private code.** A `Minimal example` is an original illustration: neutral placeholder
  names, its own structure, the same behavior. Don't mirror a private function line by line, even
  renamed.
- **Keep 1health's API vocabulary exact.** Routes, request and response fields, type keys,
  relationship names, and enum values are public platform facts — they stay as they are.

If you're unsure whether something is private, treat it as private and abstract it.

## 2. Verify against the platform

- Confirm every route against the live docs at agents.1health.io (`tools/audit-routes.ps1`). A route
  1health supports but hasn't documented must carry the `⚠ Not yet in 1health's published API docs`
  banner.
- Say what you verified and where (e.g. “verified on demo 2026-10-15”). Never include credentials,
  tokens, launch payloads, or real person data.

## 3. Keep the recipe shape

Copy [`recipes/_TEMPLATE.md`](recipes/_TEMPLATE.md). Sections stay in order: Use when · Routes ·
Reference code · Seen in · Pattern · (Primary vs fallback) · Minimal example · Gotchas · Related.
Add the recipe to [`recipes/INDEX.md`](recipes/INDEX.md).

## Before you open a PR

```bash
pwsh -File tools/check-public-refs.ps1
```

```bash
pwsh -File tools/audit-routes.ps1 -Out route-audit.md
```

```bash
pwsh -File tools/check-doc-links.ps1
```

`check-public-refs.ps1` fails on any link to a GitHub repo that isn't public. It can't tell whether
an example was copied from private code or whether a name identifies a private app — that part is
on the author and the reviewer.
