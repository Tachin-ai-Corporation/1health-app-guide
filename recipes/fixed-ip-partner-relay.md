# Relay through a fixed IP for an IP-allowlisting partner

> **Advanced / guardrailed pattern.**

**Use when:** a partner API allowlists source IPs, but your server runs on infrastructure with no
fixed egress address (most serverless hosts) — calls work, then fail on the next cold start.
**Routes:** n/a — sits inside whatever server code already talks to the partner; no 1health route
is involved.
**Reference code:** [`lib/kno2/transport.ts`](https://github.com/Tachin-ai-Corporation/v0-1health-pcp-transitional-care-management/blob/main/lib/kno2/transport.ts#L131)
**Seen in:** pcp-tcm

## Pattern

1. Confirm the symptom is really IP rotation (intermittent failures against an allowlisted API)
   before reaching for this — it's real infrastructure to run.
2. Stand up a relay with exactly one fixed IP; give the partner that address to allowlist.
3. Forward through the relay only when configured (an env var); call the partner directly otherwise
   (e.g. local dev, where your own IP is already allowed) — one function, one call site either way.
4. Enforce the target host on an allowlist **and** a shared secret, checked on both sides — either
   alone leaves an open relay that forwards credentials anywhere a caller points it.
5. Reconstruct the real response (status + body) defensively; don't assume a clean passthrough if
   the relay is built on generic automation tooling rather than a plain proxy.

## Minimal example

```ts
const ALLOWED_HOSTS = new Set(["api.partner.example.com"])

export async function partnerFetch(url: string, init: RequestInit): Promise<Response> {
  const target = new URL(url)
  if (!ALLOWED_HOSTS.has(target.host)) throw new Error(`Refusing to relay to ${target.host}`)

  const relayUrl = process.env.PARTNER_RELAY_URL
  if (!relayUrl) return fetch(url, init) // no relay configured — call directly

  const secret = process.env.PARTNER_RELAY_SECRET
  if (!secret) throw new Error("PARTNER_RELAY_URL is set but PARTNER_RELAY_SECRET is not")

  const res = await fetch(relayUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Relay-Secret": secret },
    body: JSON.stringify({ url, method: init.method ?? "GET", headers: init.headers, body: init.body }),
  })
  const { status, body } = await res.json()
  return new Response(typeof body === "string" ? body : JSON.stringify(body), { status })
}
```

## Gotchas

- Check the allowlist **and** the shared secret on both ends — dropping either makes it an open
  proxy for anyone who finds the URL.
- Only route through a relay you control — partner credentials transit it in the clear.
- This is infrastructure you own and operate — 1health has no part in it.

## Related

- [public-reference-api-proxy.md](public-reference-api-proxy.md) · [../setup/rules-of-the-road.md](../setup/rules-of-the-road.md)
