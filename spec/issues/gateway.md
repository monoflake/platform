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

## A node's private side cannot tell one app from another

A container asking `api.internal.ixc.one` for a private scope placed on another node is sent on
with `INTERNAL_TOKEN` because it is a container on the node, nothing more -- infra's
`spec/architecture/host.md`, "Every node answers the private API, and sends on what is not its
own". While every app is the author's that is the whole check; once friends' apps share nodes --
the workspace's `spec/architecture/ship-cloud.md` -- a tenant's container would reach the
platform's private scopes the same way. Each app carrying an identity of its own, which the private
side checks before it lends the platform's, is the direction; how it is issued and what each
identity may reach are undecided, and wait on accounts. Until then one gap is known: a LAN connection that reaches
Caddy through Docker's userland proxy arrives from a bridge gateway inside the app range and is
admitted as a container would be -- narrowing `APP_SOURCES` to a fixed pool for app networks, or
turning the userland proxy off, would close it.
