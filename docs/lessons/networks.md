# Networks

Facts on private networks between resources, each with its source; see `README.md`.

## Tailscale, read 2026-10-18

**The free Personal plan is for non-commercial use, and counts a tagged device among 50.** Up to 6
users, user devices unlimited, 50 tagged resources included and $1 a month each past them, 1,000
ephemeral minutes a month, 3 ACL groups; "only suitable for non-commercial use of Tailscale". The
FAQ still says 3 users and 100 devices; the pricing page is the newer. Asked of a tailnet as a
host, RFC vr5lw. Sources: https://tailscale.com/pricing/ and https://tailscale.com/kb/1251/pricing-faq

**A device joined by an OAuth client's key is tagged, and the client names its tags.** A client
given the `auth_keys` scope must be given one or more tags, and every key it makes carries tags;
"Devices registered with OAuth client credentials are tag-owned". `devices:core` reads, authorizes
and removes devices and manages their tags. Source: https://tailscale.com/kb/1215/oauth-clients

**The policy file is one document, replaced whole, guarded by its ETag.** A read returns an `ETag`;
a write replaces the whole file and, given `If-Match`, fails when the file changed since. Read from
a copy of the API reference, not Tailscale's own page, so to be confirmed. Source:
https://github.com/Lewinz/tailscale/blob/main/api.md
