# Deferred: the gateway

Where the hosts are today against the gateway (platform's `spec/architecture/gateway.md`) they are moving to:
what has to change, and what is not yet decided. The order the work is done in is a milestone once
it is agreed, not an entry here.

The rules over an entry are the index's; see web's `spec/todo/todo.md`.

## The CDN and the alias layer still stamp their own lifetimes

Both stand behind the gateway now, which answers their hosts -- `cdn.monoflake.com` and `ill.li` --
their CORS, their host files and the path rule, and stamps what leaves them from their
declarations. Each still stamps its answers itself as well, in its `cache.ts`: the gateway writes
over it, but the CDN keeps derived pictures in its own cache by that stamp, so it is not idle
there. Whether the CDN's own cache reads its lifetime from the declaration instead, and the alias
layer's stamps go, is the cleanup pass's to settle.

## An apex answers nothing yet

`monoflake.com`, `monoflake.net`, `ixc.one` and `symlink.si` are service domains, and each apex is
to answer a page saying so. Until then `monoflake.com`, `monoflake.net` and `ixc.one` have no apex
record -- `www.ixc.one`'s redirect to its apex leads nowhere -- and `symlink.si`'s root is the
gateway's redirect to the site. The pages are web's, a layer above this one, and what is decided
about them -- which host serves which, and `ill.li`'s at `il.lli.lil.ill.li` -- is web's
`spec/todo/site.md`, "The service domains answer nothing of their own yet".

## The whitelists are written by hand, and checked against the table only

`rules/ill.li/alias-paths-only.txt` spells its host's paths out by hand, and nothing checks it
against the gateway's table. The new zones --
`monoflake.com`, `ixc.one`, `symlink.si` -- have no rules at all, and `symlink.si` is not yet a
domain anything answers.

A generated whitelist has two limits to fit inside: an expression is at most 4,096 characters, and
the Free plan allows a zone five custom rules. Every deployment of `ixc.one` is in one zone, so its
whitelist covers every service on every node in one expression.

## A deployment's host is not checked against where the service runs

`geo-glo-cf.ixc.one` reads as geo on Cloudflare's Workers, and the gateway sends it to the node at
home, where geo runs, all the same: a profile's placement is read and not checked against the
service's declared placements, since every service has one placement today. Refusing a placement a
service is not at, and choosing among several where it is, come together with the gateway's choice
of where a request runs.
