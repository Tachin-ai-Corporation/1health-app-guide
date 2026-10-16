<!--
RECIPE TEMPLATE — copy this file to create a new recipe. Keep the section order fixed so an
LLM can rely on the shape. Keep it abstract and product-neutral: use placeholder type/field
names, never a specific app's hardcoded ids. Link DOWN to the live route docs on
agents.1health.io for exact contracts. Follow CONTRIBUTING.md: this repo is public, so nothing
here may link to, name, or copy from a private repo.
-->

# <Recipe title: a capability, phrased as a thing you do>

**Use when:** <the trigger — the situation in which an LLM should reach for this recipe>
**Routes:** `<METHOD /api/…>` → <link to that route's agents.md> (+ examples.md if it exists)
**Reference code:** <a link to a PUBLIC repo file (usually the app template), or exactly: none public — see the Minimal example.>
**Seen in:** <the kinds of apps that use this pattern, described generically (e.g. "a care-coordination app"); name a public repo only>

## Pattern

<The abstract strategy in a few numbered steps. This is the reusable idea, independent of any
one app. Name the engines/endpoints involved and the order of operations.>

## Primary vs fallback

<Optional — include ONLY when 1health offers two or more ways to do this job. One bullet per
approach: the primary (the default, and why), then each fallback and exactly when to switch to it.>

- **Primary — <approach>:** <why this is the default>.
- **Fallback — <approach>:** <the specific situation where you switch to it>.

## Minimal example

```ts
// The smallest correct code that demonstrates the pattern, using placeholder names.
```

## Gotchas

- <The platform quirks that bite you here, each one sentence.>

## Related

- <Links to adjacent recipes and to the relevant setup doc.>
