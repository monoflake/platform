# Domains

Facts on the names an organization is served at, and claiming a domain, each with its source; see `docs/lessons.md`.

## Names in a domain, read 2026-10-19

**No publicly trusted CA certifies a host's name with an underscore.** CA/Browser Forum Ballot SC12,
"Sunset of Underscores in dNSNames", passed in November 2018, ended the exception that had let
them through, since RFC 5280 never allowed them; certificates with one were cut to 30 days and
phased out in 2019. Asked by checklist B3. Sources:
https://lists.cabforum.org/pipermail/servercert-wg/2018-November/000362.html and
https://ssl.com/?p=26132

**A site's reserved usernames are listed by shouldbee/reserved-usernames**, 602 names under MIT,
last changed 2021-07-14: paths a site keeps from its users, as `admin`, `api`, `login`, `settings`,
`status`, `www`, `mail` and `ns1`, with a few misspellings and Spanish and Portuguese words among
them. 577 fit a name of 3 or more lowercase letters, digits and hyphens. Asked by checklist B3.
Source: https://github.com/shouldbee/reserved-usernames, kept in `vendor/reserved-usernames/`

**RFC 2142 names the mailboxes a domain keeps**: `info`, `marketing`, `sales` and `support` for a
business; `abuse`, `noc` and `security` for network operations; `postmaster`, `hostmaster`,
`usenet`, `news`, `webmaster`, `www`, `uucp` and `ftp` for its services. Asked by B3. Source:
https://www.rfc-editor.org/rfc/rfc2142.html

## Claiming a domain, read 2026-10-19

**`/.well-known/` is RFC 8615's prefix for metadata of a whole origin**, in HTTP, HTTPS, WS and WSS
URIs, kept apart from the origin's own paths. "Applications that wish to mint new well-known URIs
MUST register them", by Specification Required; a suffix holds no `/`. ACME's HTTP challenge fetches
`/.well-known/acme-challenge/{token}`. Asked of a domain's proof, RFC vr5lw. Source:
https://www.rfc-editor.org/rfc/rfc8615.html

**Cloudflare for SaaS proves a custom hostname by a TXT record or an HTTP token**, the latter at
`/.well-known/cf-custom-hostname-challenge/{id}`, answered 200 with a body it gives, fetched with
the User-Agent "Cloudflare Custom Hostname Verification"; for a customer that cannot change its DNS
or take downtime. Pre-validation is not offered for O2O hostnames, which validate in real time. Asked
by C26. Source:
https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/domain-support/hostname-validation/pre-validation/

**RDAP is where a gTLD's registration is read since 2025-01-28**, ICANN's date for WHOIS's sunset.
An answer is JSON whose `events` each hold an `eventAction` and an `eventDate` in RFC 3339; the
action `expiration` is registered, and may be dated in the future. `example.com` answered,
2026-10-19, registration 1995-08-14 and expiration 2027-08-13. IANA's bootstrap of 2026-09-30 names
an RDAP server for 1203 TLDs, `com`, `net`, `org`, `dev`, `app`, `fyi`, `ai` and `uk` among them,
and none for `io`, `cn`, `de`, `jp`, `us` or `co`. Asked of a domain's proof, RFC vr5lw. Sources:
https://www.icann.org/en/announcements/details/icann-update-launching-rdap-sunsetting-whois-27-01-2025-en,
https://www.rfc-editor.org/rfc/rfc9083.html and https://data.iana.org/rdap/dns.json
