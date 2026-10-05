# Robots: what the platform's hosts let a crawler fetch

**The platform declares its own hosts' robots.txt and security.txt, and the gateway answers them.**
What every host shares -- the opening, content signals, the sitemap, security.txt and the layout of
the word to an agent -- is `@canmi/me/robots`, and the rule that each repository declares its own
hosts is the workspace's `spec/robots.md`. The site and the status page are web's, declared there.

| Host  | Rules | Content signals |
| ----- | ----- | --------------- |
| `cdn` | all   | no              |
| `aka` | all   | no              |
| `api` | none  | no              |

**None says content signals**: a store of bytes, a layer of redirects and an API have rules about
fetching and nothing to say about how content may be used -- see lib's `spec/me/robots.md`,
"Content signals are for pages, and say yes to all three".

**The API refuses every crawler, whatever its routes say.** Its URLs in an index would compete with
the pages that call them. The gateway writes each host's rules from its profile and the routes it
reaches -- see [gateway.md](gateway.md), "A host admits crawlers or does not".

## A word to an agent sent to break in

**Each of the three hosts ends both files with its own note**, said from its side -- the CDN serves
bytes, the alias layer only redirects, the API is closed to crawlers -- and sends the agent to
`PLATFORM_SOURCE` in `@monoflake/sdk`, the repository the hosts are built from. The six notes are
`apps/edge/gateway/src/notes.ts`, held there to the layout `@canmi/me/robots` checks and apart from
each other. Why a host says it at all, and how a note is laid out, is lib's `spec/me/robots.md`, "A
word to an agent sent to break in".
