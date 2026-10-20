# Certificates

Facts on the public certificate authorities a machine is certified by, each with its source; see `docs/lessons.md`.

## Let's Encrypt, read 2026-10-18

**A registered domain gets 50 certificates a week, and the Public Suffix List says what one is.**
"Up to 50 certificates can be issued per registered domain ... every 7 days", across all accounts;
"We use the Public Suffix List to identify registered domains." "Up to 300 new orders can be created
by a single account every 3 hours." A renewal coordinated by ARI is "exempt from all rate limits";
one for the exact same names is exempt from the order and registered-domain limits. A certificate for the exact same set of names is issued at most 5 times
every 7 days, across all accounts. Asked of names
the platform gives machines, RFC vr5lw. Source: https://letsencrypt.org/docs/rate-limits/

**The Public Suffix List takes a private domain by a pull request, and turns away one made to escape
a rate limit.** A suffix is added under the private domains, validated by a `_psl` TXT record whose
value is the pull request's address, by a domain with more than two years of registration left. It
is likely declined when its sole purpose is to get around a third party's rate limits -- Let's
Encrypt has a form of its own for those -- or when the project serves fewer than thousands of users;
review has no promised time, and clients take a change up on their own schedules. Asked of names the
platform gives organizations, RFC vr5lw, read 2026-10-18. Source:
https://github.com/publicsuffix/list/wiki/Guidelines

## Google's public CA, read 2026-10-18

**Google's public CA takes 100 orders an hour a project, and names no limit a domain.** It is
reached by ACME with external account binding, each ACME account bound to a Google Cloud project,
whose accounts share the project's quotas: 100 `newOrder` an hour, 300 `newAuthz` an hour, 100
`newAccount` an hour, and adjustments may be asked. Wildcards are validated by the DNS challenge
alone. No limit a domain is listed for it, and its price and certificates' lifetime are not on the
page. Asked of names the platform gives machines, RFC vr5lw. Sources:
https://docs.cloud.google.com/certificate-manager/docs/public-ca and
https://docs.cloud.google.com/certificate-manager/docs/quotas
