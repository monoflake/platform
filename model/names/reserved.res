/**
 * The names no username or label is given by the ordinary flow, on any platform, since either may
 * stand in a domain name, v7v3w. Reserved means kept
 * for the platform: the operator alone gives one, by hand, to an organization of the platform's
 * own. The list only grows, and a name added that someone holds stays theirs.
 */
/**
 * The names a site keeps from its users, as shouldbee/reserved-usernames lists them, read by the
 * check.
 */
let vendored = "vendor/reserved-usernames/reserved-usernames.json"

/**
 * The mailboxes RFC 2142 names, so no one holds `abuse`, `noc` or `security` of a domain the
 * platform serves, `docs/lessons/domains.md`.
 */
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

/** The platform's own words; the hosted platform's are given beside, RFC 8lkuv. */
let ownWords = [
  "monoflake",
  "platform",
  "gateway",
  "storage",
  "database",
  "compute",
  "footing",
  "issuer",
  "deployer",
  "operator",
]

/** The providers a sign-in shows. */
let providers = ["cloudflare", "google", "apple", "github"]

type own = {label: string, what: string}

let words = Array.concat(ownWords, Fill.part("words")->Option.getOr([]))

/** The labels the operator gives the platform's own organizations, the hosted platform's own. */
let own: array<own> = Fill.part("labels")->Option.getOr([])
