# The repository

The platform of the author's system: the services every site reads and the doors they are read
through. The node's apps -- `geo`, `objects`, `postgres`, `ledger`, `cron`, `apt`, `apk`, `shot`, `probe`,
`telemetry`, `gemini` and `grok`, and the `gateway` and `quota` that also run at home -- and the Workers
Cloudflare builds, `aka`, `cdn`, `gateway`, `hook` and `quota`. `libs/sdk` is what a consumer of
the platform reads, `libs/probe` the status database's schema, `libs/ledger` what the node's
services share, and `libs/packages` what `apt` and `apk` share. `rules/` holds
each zone's firewall rules, which `mise run rules` checks and deploys; see
[architecture/firewall.md](architecture/firewall.md). Why the system is cut into this layer,
infra's and the services', is the workspace's `spec/architecture/layers.md`, the picture of all
four repositories; the rules every repository keeps are the workspace's `spec/`, and what is here is
what the platform alone decides.

## `apps/` is deployed, `libs/` is imported

Every app has a directory under `apps/<group>/` with its `service.toml`, and an app host runs has
its `Dockerfile` beside it; every library one under `libs/`. A crate is listed in `Cargo.toml` by
hand and a package found by `pnpm-workspace.yaml`'s globs, so a TypeScript-only directory never
breaks Cargo.

**The apps are grouped by what each does**, since a category of them passed the four members the workspace's `spec/architecture/repos.md`, "Grouping threshold", lets a flat `apps/` hold:

| Group      | Apps                            | What they are                                                            |
| ---------- | ------------------------------- | ------------------------------------------------------------------------ |
| `edge`     | gateway, quota, hook            | the door a request comes in by, its limits, and CI's                     |
| `delivery` | cdn, aka                        | the bytes, and the names that point at them                              |
| `data`     | objects, postgres, ledger       | what holds state                                                         |
| `observe`  | probe, telemetry                | the platform watched, from outside and from inside                       |
| `system`   | cron, apt, apk, deployer, relay | the platform's own schedule, deploys and messages, and the machine's own |
| `compute`  | geo, shot                       | what a caller asks to be worked out                                      |
| `model`    | gemini, grok                    | a model a subscription reaches, served as an API                         |

**A group is a directory and nothing more.** An app's name is still its directory's own and unique
across the groups: an image, a container, a scope and a `dev-` task are named for the app, never for
its group, so moving an app between groups changes no name on the node. The tools find an app by
`apps/*/<name>`, and the groups are whatever directories `apps/` holds.

## The other repositories are named, never linked

Infra is `monoflake/infra`, the site `canmi21/web` and the library `canmi21/lib`, each cloned
beside this one in the workspace. A rule of theirs is cited by name -- `infra's spec/architecture/host.md` -- and `refs`
resolves it in that repository when it is cloned beside this one, so a renamed section still fails
here. A relative link across a repository resolves only while both are cloned side by side, so a
spec here never writes one. `mise run rules` reads the site's routes the same way, from the web
repository cloned beside this one, and says so when it is not.

## The Workers run in development beside the site

`dev-gateway`, `dev-cdn`, `dev-quota` and `dev-aka` run the Workers under `wrangler dev`, each on
its pinned port, as web's `spec/toolchain.md` has under "Dev ports are pinned"; the base session
starts them from this checkout, and the site's dev server reaches the alias layer and the CDN
through its own `/alias`, `/symlink` and `/cdn`.

## An app deployed elsewhere asks for its scope here

The gateway's scope table is generated from every declaration it routes, and one of them is not
this repository's: the site answers its API from its own Worker, which the web repository deploys.
Its declaration is copied into `apps/edge/gateway/elsewhere/`, one file an app, and `mise run scopes`
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

**A release runs the whole repository's tests first, and waits for the next change to the package
when they fail.** The test step is every suite here, not the package's alone, so a test anywhere
that fails stops the publish. A fix that does not touch the package does not trigger the workflow,
so the unpublished change goes out with the next push that changes the package, or by running the
workflow by hand -- as on 2026-10-08, when the deployer's admission test refused a route the
gateway gained in the same push as a change to `@monoflake/sdk`.

This repository continues the history of `canmi21/web`, which was `canmi21/lattice`, from the commit
the three repositories split at; everything before it is shared with the other two.
