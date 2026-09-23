# URL-driven state

**Use when:** a user can land on a deep, specific view (reached by search, a bookmark, browser back/forward, or a shared link) with no client-side state already loaded — the page must reconstruct everything it shows from the URL alone.
**Routes:** n/a — reuses whichever read route the view already calls (see [query-the-data-graph.md](query-the-data-graph.md) / [grid-list-views.md](grid-list-views.md)); this recipe governs *when* you call it, not a route of its own.
**Reference code:** [`components/home-page-client.tsx`](https://github.com/Tachin-ai-Corporation/v0-1health-secure-share/blob/main/components/home-page-client.tsx), [`contexts/navigation-context.tsx`](https://github.com/Tachin-ai-Corporation/v0-1health-secure-share/blob/main/contexts/navigation-context.tsx)
**Seen in:** secure-share · 1health platform usage (resolve-once-into-URL, step deep-linking)

## Pattern

1. Treat the URL's query string (or path segments) as the **only** durable client-side state for "which view, which record" — put identifiers there, not in a global store or a prop chain that a fresh page load can't reproduce.
2. On navigation, push both a URL (`history.pushState`) and the matching in-memory view state together, so back/forward and a hard reload agree on what should render.
3. On mount (and on `popstate`), parse the current URL first. If the in-memory state needed to render the view is missing — the fresh-load / shared-link / back-button case — treat the URL params as the seed for a **restore fetch**, not an error.
4. The restore fetch should reuse the **same** read path/query the normal navigation flow uses (the same list/grid call), not a bespoke "fetch one record by id" shortcut — so restored state and normally-navigated state can never disagree in shape or in what scoping/filtering they apply.
5. Gate the restore on whatever session context it needs (e.g. the caller's own tenant id, to cross-check ownership) — fire it only once that's available, and render a loading state, not the empty view, while it resolves.
6. On a failed restore (record not found among what the caller can see), fall back to a safe default view rather than rendering broken or partial state.
7. A narrower, very common case of the same idea: when a single value has to be **resolved** through
   an API call but is otherwise stable for the life of the page (e.g. which step a key currently maps
   to), don't just keep the resolved value in memory — write it into a URL param via a
   history-replacing update the moment you have it, and skip the lookup entirely whenever that param
   is already present and well-formed. Treat any unparseable value the same as a missing one, so a
   stale or hand-edited URL retriggers the lookup instead of silently misbehaving downstream.
8. This same idea also works one level deeper, for a **transient overlay** representing one
   in-progress step of a running instance (an order, a campaign-sourced journey): carry both the
   running instance's id and the target step's id as URL params, and open the step overlay directly
   on mount when both are present, instead of requiring navigation through a list first. Share one
   overlay component across whichever kinds of "running instance" your app has, discriminated by an
   explicit `type` param, since the step UI itself doesn't need to know which kind it's showing.
9. On closing that overlay, delete both params from the URL outright — don't just hide the
   component — or a browser back/forward lands right back on the URL that reopens it.

## Minimal example

```tsx
function useUrlParam(key: string): string | null {
  return new URLSearchParams(window.location.search).get(key)
}

function AppShell() {
  const { currentView, setCurrentView } = useNavigation()
  const [detail, setDetail] = useState<DetailData | null>(null)
  const needsRestore = currentView === "detail" && !detail
  const idsParam = needsRestore ? useUrlParam("ids") : null

  useSWR(
    idsParam && user?.tenantId ? `restore:${idsParam}:${user.tenantId}` : null,
    async () => {
      const targetIds = new Set(idsParam!.split(",").map(Number))
      const page = await fetchListPage(0, 100)                // SAME call the normal nav path uses
      const match = page.data.find((row) => targetIds.has(row.id))
      if (!match) { setCurrentView("list"); return null }      // safe fallback, not a broken render
      setDetail(toDetailData(match))
      return null
    },
  )

  return currentView === "detail"
    ? detail ? <DetailView data={detail} /> : <LoadingState />
    : <ListView onOpen={(row) => {
        setDetail(toDetailData(row))
        setCurrentView("detail", { ids: String(row.id) })
      }} />
}
```

## Gotchas

- **Put global identifiers in the URL, never local-only ids** — a row number that only means something to the currently-loaded list is useless to a page starting from nothing.
- **Reuse the list/grid read path for restore** — a bespoke "get by id" call is a second code path that can silently diverge in filtering/shape from the one normal navigation uses (it might, for instance, skip the same ownership scoping).
- **Gate restore on session/tenant context being ready** — firing the restore fetch before you know who's asking risks a wasted call, or worse, resolving against the wrong scope.
- **`popstate` needs its own care** — a `pushState` you issued yourself and a browser back/forward event both fire through the same listener; make sure programmatic navigation doesn't re-trigger your own restore logic in a loop.
- **A programmatic overlay close and a real back/forward navigation flow through that same
  listener** — make sure the overlay's own close handler (which removes its URL params) doesn't get
  misread as "the user navigated here again" and immediately reopen itself.

## Related

- [query-the-data-graph.md](query-the-data-graph.md)
- [grid-list-views.md](grid-list-views.md)
- Concepts: [setup/prototype-to-app.md](../setup/prototype-to-app.md)
