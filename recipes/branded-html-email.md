# Send branded HTML email without CSS

**Use when:** you send transactional email through 1health and want it to look like your app: a
brand color, a wordmark, a button. Or a send through `/v2/email/send/html` comes back **403 with an
HTML page** instead of a 1health JSON error.
**Routes:** `POST /api/v2/email/send/html` → [agents.md](https://agents.1health.io/public/prod/api/v2/email/send/html/agents.md)
**Reference code:** [`lib/email/layout.ts`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/lib/email/layout.ts) (the renderer and its firewall guard) · [`scripts/verify-email-layout.mjs`](https://github.com/chill-tachin/expertdx-ordering-provider/blob/main/scripts/verify-email-layout.mjs) (tests)
**Seen in:** expertdx (practice invitations, email notifications). The firewall behavior was measured
on production (`app.1health.io`) on 2026-10-16; check it against demo before relying on it there.

## Pattern

1. **Know the filter.** A firewall in front of 1health's email routes refuses the request, with a 403
   and an nginx HTML page before 1health ever sees it, when the body contains **any** of:
   - a `style="…"` attribute,
   - a `<style>` block,
   - a `<!doctype …>`.

   It does this whatever the credential: a service key and a user token were refused alike. Plain
   text, and HTML without those three, goes through.
2. **Style the way email was styled before CSS.** Every one of these passed:
   - tables with `bgcolor`, `width`, `height`, `align`, `valign`, `border`, `cellpadding` and `cellspacing`;
   - `<font color face size>`;
   - `<b>`, `<i>`, `<h1>`–`<h3>`, `<ul>`/`<ol>`, `<hr>`, `<br>`, `<center>` and `<div align>`;
   - `<img src width height alt>` and `<a href>`;
   - HTML entities;
   - `<html><body bgcolor>` with no doctype.

   That's enough for a branded layout:
   - a colored band (a short table cell with `bgcolor`);
   - a wordmark (`<font face color>`);
   - a button (a `bgcolor` table cell around a link);
   - a tinted panel and footer.
3. **Build every email through one renderer.** It escapes all interpolated text, and it **asserts
   the result is firewall-safe before sending**. Then a later edit that slips in an inline style
   fails in your tests, not as a silent 403 in production.
4. **Send with the minimal DTO,** exactly as in [native-email-and-sms.md](native-email-and-sms.md):
   `{ userEmail, subject, text }`, where `text` is the HTML and `userEmail` is the recipient. Send one
   recipient per call.
5. **Probe new markup without spamming anyone.** Send each candidate fragment to a reserved,
   non-deliverable address such as `probe@example.com`. 403 means the firewall refuses it; 200 means
   it passed. Then send one real sample to an inbox you control to check how it renders.

## Primary vs fallback

- **Primary — style-free branded HTML (this recipe):** the default for any email a person will read,
  such as invitations, notifications and receipts. It looks like your app and is never refused.
- **Fallback — plain text:** send no markup when there's nothing to brand (an internal alert, a
  one-line confirmation). It always passes.
- **Not a fallback:** inline CSS, a `<style>` block or a full HTML document copied from an email
  builder. They're refused, so convert them to the attribute style above.

## Minimal example

```ts
// One renderer for every email: escaped text, legacy attributes only, checked before sending.
const BRAND = { primary: "#12332f", accent: "#e8765a", tint: "#f3f6f3", ink: "#26332f", muted: "#66766f" }
const SANS = "Arial, Helvetica, sans-serif"

const esc = (s: string) =>
  s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!)

/** What the firewall refuses (403), so you find out in tests instead. */
export function firewallProblem(html: string): string | null {
  if (/style\s*=/i.test(html)) return "a style attribute"
  if (/<style[\s>]/i.test(html)) return "a <style> block"
  if (/<!doctype/i.test(html)) return "a doctype"
  return null
}

export function renderEmail(o: {
  heading: string
  body: string[]
  button: { label: string; href: string }
  footer: string
}): string {
  const para = (t: string) => `<p><font face="${SANS}" size="3" color="${BRAND.ink}">${esc(t)}</font></p>`
  const html =
    `<html><body bgcolor="${BRAND.tint}">` +
    `<table width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="${BRAND.tint}"><tr><td align="center"><br>` +
    `<table width="560" cellpadding="0" cellspacing="0" border="0" bgcolor="#ffffff">` +
    `<tr><td bgcolor="${BRAND.primary}" height="6"></td></tr>` + // brand band
    `<tr><td><table width="100%" cellpadding="28" cellspacing="0" border="0"><tr><td>` +
    `<font face="Georgia, serif" size="5" color="${BRAND.primary}">YourApp</font>` + // wordmark
    `<h2><font face="${SANS}" color="${BRAND.primary}">${esc(o.heading)}</font></h2>` +
    o.body.map(para).join("") +
    // Button: a colored cell around the link; <font> inside the <a> sets the link's text color.
    `<table cellpadding="13" cellspacing="0" border="0"><tr><td bgcolor="${BRAND.accent}" align="center">` +
    `<a href="${esc(o.button.href)}"><font face="${SANS}" size="3" color="#ffffff"><b>${esc(o.button.label)}</b></font></a>` +
    `</td></tr></table>` +
    `</td></tr></table></td></tr>` +
    `<tr><td bgcolor="${BRAND.tint}"><table width="100%" cellpadding="20" cellspacing="0" border="0"><tr><td>` +
    `<font face="${SANS}" size="2" color="${BRAND.muted}">${esc(o.footer)}</font>` + // footer
    `</td></tr></table></td></tr>` +
    `</table><br></td></tr></table></body></html>`
  const problem = firewallProblem(html)
  if (problem) throw new Error(`1health's email firewall would refuse this: it has ${problem}`)
  return html
}

/** Server-side send. Exactly these three fields; one recipient per call. */
export async function sendEmail(baseUrl: string, token: string, to: string, subject: string, html: string) {
  const res = await fetch(`${baseUrl}/api/v2/email/send/html`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ userEmail: to, subject, text: html }),
  })
  if (res.status === 403 && (res.headers.get("content-type") ?? "").includes("text/html")) {
    throw new Error("Refused by the email firewall (markup), not by 1health")
  }
  return res.ok
}
```

## Gotchas

- **A 403 here is usually the firewall, not a permission problem.** It answers with an HTML page
  (`<title>403 Forbidden</title>`), not 1health's JSON error. Check the markup before you go looking
  for a missing permission.
- **The credential doesn't matter.** The same body is refused on a service key and on a user's own
  token, so switching tokens won't help.
- **Links default to the mail app's blue.** Put a `<font color>` inside the `<a>` to color the link
  text.
- **No hidden preview text.** The usual "preheader" trick needs `display:none`, which is CSS. The
  inbox preview shows the first visible text, so make the heading say what happened.
- **Use a fixed-width table (`width="560"`).** There are no media queries; mobile mail apps scale it
  down.
- **Escape every interpolated value,** names and URLs included. The renderer is the only place that
  writes tags.
- **Mail comes from `noreply@app.1health.io`.** Put your app's name in the subject or heading so
  people know who it's from.
- **Don't put patient details in email:** an identifier and a link to sign in are enough. Email is
  not a secure channel.

## Related

- [native-email-and-sms.md](native-email-and-sms.md) — the send routes, the minimal-DTO rule, and
  which token to use.
- [message-a-partner-contact-point.md](message-a-partner-contact-point.md) — messaging a partner's
  email, fax or mobile contact point.
- [step-config-notifications-webhooks.md](step-config-notifications-webhooks.md) — emails 1health sends itself
  when a workflow step completes, in its own template (not subject to this recipe).
- Concepts: [setup/anti-patterns.md](../setup/anti-patterns.md) — no third-party mailer as a way around this.
