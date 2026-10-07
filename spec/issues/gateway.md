# Issues: the gateway

Where the hosts are today against the gateway (platform's `spec/architecture/gateway.md`) they are moving to:
what is not yet decided. Once an entry is decided it leaves for [../todo/todo.md](../todo/todo.md).

The rules over an entry are the index's; see [issues.md](issues.md).

## The CDN and the alias layer still stamp their own lifetimes

Both stand behind the gateway now, which answers their hosts -- `cdn.monoflake.com` and `ill.li` --
their CORS, their host files and the path rule, and stamps what leaves them from their
declarations. Each still stamps its answers itself as well, in its `cache.ts`: the gateway writes
over it, but the CDN keeps derived pictures in its own cache by that stamp, so it is not idle
there. Whether the CDN's own cache reads its lifetime from the declaration instead, and the alias
layer's stamps go, is the cleanup pass's to settle.

## The whitelists are written by hand, and checked against the table only

`rules/ill.li/alias-paths-only.txt` spells its host's paths out by hand, and nothing checks it
against the gateway's table. The new zones -- `monoflake.com`, `monoflake.net`, `ixc.one`,
`symlink.si` -- carry the shared rate cap and their redirects, and no whitelist yet.

A generated whitelist has two limits to fit inside: an expression is at most 4,096 characters, and
the Free plan allows a zone five custom rules. Every deployment of `ixc.one` is in one zone, so its
whitelist covers every service on every node in one expression.

## A deployment's host is not checked against where the service runs

`geo-glo-cf.ixc.one` reads as geo on Cloudflare's Workers, and the gateway sends it to the node at
home, where geo runs, all the same: a profile's placement is read and not checked against the
service's declared placements, since every service has one placement today. Refusing a placement a
service is not at, and choosing among several where it is, come together with the gateway's choice
of where a request runs.

## Inside the house, an ordered service is asked on the wrong node

The gateway the house's own callers reach -- rdu's, which the resolver answers `api.monoflake.com`
with -- binds only `RDU` (`apps/edge/gateway/src/node.ts`), so a service declared `ordered` with
another node first is asked on rdu from the LAN and the tailnet and on its first placement from
everywhere else. For `shot`, whose tasks stay on the node that took them, a task started from
outside and asked after from inside is not found. Seen on 2026-10-07: a task taken through
Cloudflare lived on `tyo`, and the same request from the LAN reached rdu's `shot`. The house's
gateway could reach the other nodes over the tailnet, hand a scope whose first placement is not
its own node to the public gateway, or keep answering locally and accept the split; each changes
"Inside the house, the same names answer locally" in [../architecture/gateway.md](../architecture/gateway.md).
