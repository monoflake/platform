/**
 * The names no username or label is given by the ordinary flow, on the internal platform and the
 * external alike, since either may stand in a domain name, v7v3w. Reserved means kept for the
 * platform: the operator alone gives one, by hand, to an organization of the platform's own. The
 * list only grows, and a name added that someone holds stays theirs.
 */
/** The names a site keeps from its users, as shouldbee/reserved-usernames lists them, read by the check. */
let vendored = "vendor/reserved-usernames/reserved-usernames.json"

/** The mailboxes RFC 2142 names, so no one holds `abuse`, `noc` or `security` of a domain the platform serves, `docs/lessons/domains.md`. */
let mailboxes = [
  "info",
  "marketing",
  "sales",
  "support",
  "abuse",
  "noc",
  "security",
  "postmaster",
  "hostmaster",
  "usenet",
  "news",
  "webmaster",
  "www",
  "uucp",
  "ftp",
]

/** The platform's own words. */
let words = [
  "monoflake",
  "mofl",
  "platform",
  "console",
  "gateway",
  "storage",
  "database",
  "compute",
  "footing",
  "anchor",
  "issuer",
  "deployer",
  "operator",
]

/** The providers a sign-in shows. */
let providers = ["cloudflare", "google", "apple", "github"]

type own = {label: string, what: string}

/** The platform's own organizations, each given its reserved label by the operator. */
let own: array<own> = [{label: "console", what: "the console's dashboard, opened first, v7v3w"}]
