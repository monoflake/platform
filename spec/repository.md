# The repository

The platform of the author's system: the services every site reads and the doors they are read
through. The node's apps -- `geo`, `objects`, `postgres`, `ledger`, `cron`, `apt`, `shot`, `probe`,
`telemetry`, `gemini`, and the `gateway` and `quota` that also run at home -- and the Workers
Cloudflare builds, `aka`, `cdn`, `gateway`, `hook` and `quota`. `libs/sdk` is what a consumer of
the platform reads, `libs/probe` the status database's schema, and `libs/ledger` what the node's
services share. Why the system is cut into this layer, infra's and the services', is
[architecture/layers.md](architecture/layers.md).

## `apps/` is deployed, `libs/` is imported

Every app has a directory under `apps/` with its `service.toml`, and an app host runs has its
`Dockerfile` beside it; every library one under `libs/`. A crate is listed in `Cargo.toml` by hand
and a package found by `pnpm-workspace.yaml`'s globs, so a TypeScript-only directory never breaks
Cargo.

## The other repositories are named, never linked

Infra is `monoflake/infra` and the site `canmi21/web`, each cloned beside this one in the
workspace. A rule of theirs is cited by name -- `infra's spec/architecture/host.md` -- and `refs`
resolves it in that repository when it is cloned beside this one, so a renamed section still fails
here. A relative link across a repository resolves only while both are cloned side by side, so a
spec here never writes one. `mise run rules` reads the site's routes the same way, from the web
repository cloned beside this one, and says so when it is not.

## An app deployed elsewhere asks for its scope here

The gateway's scope table is generated from every declaration it routes, and one of them is not
this repository's: the site answers its API from its own Worker, which the web repository deploys.
Its declaration is copied into `apps/gateway/elsewhere/`, one file an app, and `mise run scopes`
reads them beside the apps here. A change to such an app's API arrives here as a change to its copy,
which is the platform granting the scope.

## Publishing

**`@monoflake/sdk` and `@monoflake/probe` are dated**, `YYYY.MDD.N`, and published by
`.github/workflows/release.yml` whenever a push changes one, as the lib repository publishes its
own -- its `spec/repository.md`, "Versions and publishing", holds the scheme and why. Here each is
read as TypeScript from source; `publishConfig` points what is published at `dist/`, which tsdown
builds, because a consumer's node does not strip types inside `node_modules`. Each first version
was published by hand, as `0.0.0`, since npm attaches a trusted publisher only to a package that
exists. `@monoflake/urls` is infra's, installed from npm like any other package.

This repository continues the history of `canmi21/web`, which was `canmi21/lattice`, from the commit
the three repositories split at; everything before it is shared with the other two.
