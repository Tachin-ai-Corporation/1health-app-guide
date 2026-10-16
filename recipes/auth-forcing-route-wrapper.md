# Force authorization with a route wrapper

**Use when:** every route in a privileged area must resolve and authorize the caller before doing
anything else, and you want skipping that check to be **structurally impossible**, not just a
convention someone has to remember.
**Routes:** n/a — a server-side code-structure pattern, applied around whichever routes need it.
**Reference code:** none public — see the Minimal example.
**Seen in:** A specialist-consult ordering app

## Pattern

1. Write a wrapper function that is the **outermost shape of every route handler** in the privileged
   area: it resolves the caller (see
   [server-side-authorization.md](server-side-authorization.md)), does whatever authorization the
   route needs, and only then calls the route's own logic as a callback with the validated values.
2. Give a resource-scoped variant a signature that takes the resource's id and hands the callback
   back **both** the caller and the already-authorized resource — so reaching the data at all
   requires having passed the check.
3. Centralize error→HTTP mapping inside the wrapper (401 no session, 403 not-yours, 500 anything
   else) so no route body decides what an auth failure returns, and so an upstream error's details
   are logged server-side but never echoed to the caller.
4. Keep the callback's parameters narrow — just the caller and the pre-validated id/resource. If a
   handler reaches back into the raw request for something the wrapper already validated, the
   wrapper stops being the one choke point.
5. Coerce and reject malformed input (a non-numeric id, unparseable JSON) inside the wrapper too,
   throwing the same error type "not found" would — a malformed id shouldn't behave differently from
   a well-formed one that simply isn't the caller's.

## Minimal example

```ts
// route-guard.ts
// The ONE place a thrown error becomes a status: 401 / 403 / generic 500 (real error logged server-side).
async function respond<T>(work: () => Promise<T>): Promise<Response> {
  try {
    return Response.json(await work())
  } catch (error) {
    return errorResponseFor(error)
  }
}

export const withSignedInUser = <T>(fn: (user: SignedInUser) => Promise<T>) =>
  respond(async () => fn(await requireSignedInUser()))

export const withOwnedRecord = <T>(
  rawId: unknown,
  fn: (user: SignedInUser, id: number, record: OwnedRecord) => Promise<T>,
) =>
  respond(async () => {
    const user = await requireSignedInUser()
    const id = parseRecordId(rawId) // garbage input throws AccessDeniedError, same as "not yours"
    return fn(user, id, await authorizeRecord(user, id))
  })

// app/api/records/[id]/archive/route.ts — the whole route
export const POST = (_req: Request, { params }: { params: { id: string } }) =>
  withOwnedRecord(params.id, (_user, id) => archiveRecord(id))
```

## Gotchas

- It only helps if **every** route in the area goes through it — one handler that reaches for
  privileged data directly defeats the whole point.
- Don't let a handler read request internals the wrapper already resolved — that reopens the path
  the wrapper exists to close.
- Log the real upstream error; return a generic message — an upstream body can carry details (tenant
  names, internal ids) the caller shouldn't see.

## Related

- [server-side-authorization.md](server-side-authorization.md) · [split-identity-service-key.md](split-identity-service-key.md)
