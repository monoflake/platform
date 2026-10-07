# The deployer: Workers deployed as host deploys images

The platform's roadmap, "Apps are deployed through the platform, Workers carrying only their
stateless part", decided the direction; this file is how. Until a Worker moves, it is deployed by
Cloudflare's Git integration as [services.md](services.md) says.

## One deployer, on one node

**`deployer` is a platform service, `apps/system/deployer`, placed on `tyo` alone.** A Worker deploy
is global, so there is exactly one; a standby waits on the platform scheduler's lease --
[scheduling.md](scheduling.md). A deployer that is down means nothing deploys and nothing stops
serving, as host's control plane going down is not an outage -- infra's
`spec/architecture/host.md`. It is TypeScript on Node, because wrangler is, and it deploys one
Worker at a time.

**It learns of a run from the hook, as a third receiver beside host and keeper.** The hook posts the
same `{run, repository}` to `deployer.<suffix>/notice` through the bindings of the nodes the
deployer's `service.toml` places it on, a list generated into the hook from that declaration as the
gateway's table is from its services. Later the notice comes off the relay's log, and a deployer
that was down catches up -- [relay.md](relay.md).

**It trusts nothing the notice says.** It asks GitHub for the run and refuses it unless it is one of
its sources' `.github/workflows/deploy.yml`, on `main`, completed and successful -- host's own check
-- then downloads the artifacts named `worker-<app>` and checks each digest GitHub recorded. host
takes only `deploy-` artifacts and the deployer only `worker-` ones, so neither sees the other's.

## What a Worker artifact is

**CI packages a Worker without a credential; the deployer deploys it without the source.** An app
whose `placements` names `workers` and whose directory holds a `wrangler.jsonc` gets a
`worker-<app>` artifact, built once for every architecture: `wrangler deploy --dry-run --outdir`'s
bundle, the static assets when it has them, its `service.toml`, and the `wrangler.jsonc` resolved to
`wrangler.json` with `no_bundle` set and its paths pointed into the artifact. Each repository's
`.mise/tasks/worker` writes it, the twin of `.mise/tasks/image`, so a local run and CI cannot
package differently. The deployer runs `wrangler deploy --config wrangler.json` in that directory.
An app that also has a `Dockerfile` and names nodes gets `deploy-<app>-<arch>` as well; the console
is the first with both.

**wrangler rather than the API**: the API's assets path is a manifest, an upload session, base64
buckets and a completion token, with custom domains on an endpoint of their own, and the docs do
not name the assets' hash. wrangler does all of it and keeps up with new binding types; the API is
the fallback if wrangler ever fights an artifact with no source.

**An app's bindings are declared to the platform and written by the deployer.** A `[worker]`
section of `service.toml` names each binding the app wants by the platform's vocabulary -- a
Durable Object, a KV namespace, a bucket, the nodes, `geo` -- and the deployer resolves each to
Cloudflare's product or the platform's service and writes it into the Worker's configuration, so an
app never names a Cloudflare id. Until that section exists, a Worker names its own bindings in
`wrangler.jsonc`, VPC services included, and the deployer passes them through.

## What it refuses

**A Worker's name belongs to one repository, and only that repository's runs deploy it.** The
deployer's configuration on its node holds `WORKER_OWNERS`, each Worker's name against its
`owner/repo`, and a name nobody owns is refused -- without it, admitting a repository would hand it
every Worker on the account. Each owner has the zones its routes and custom domains may be on. **No
binding type is refused by layer**: the platform exports every binding Workers have and its own
beside them -- the workspace's `spec/architecture/layers.md`, "Cloudflare is under the platform,
and an app binds only the platform" -- so a Durable Object is as much an app's to ask for as an IP
lookup. **A resource a binding names belongs to one repository too**: outside the
home organization, a Worker may bind only the databases, buckets, namespaces, queues, secrets and
Workers its repository is given in `WORKER_RESOURCES`, or that its repository owns -- the nodes'
VPC services and the account's AI and browser included, since each reaches past the Worker; only
what names nothing shared, its own Durable Objects, assets, vars and secrets, passes unlisted. A
Durable Object class taken from another Worker counts as binding that Worker. Once
apps declare their bindings to the platform, the platform gives each its own and this list is what
it gave.

**It records each deploy as host does**: stages -- downloading, admitting, uploading, then deployed
or failed -- the version Cloudflare returns, and wrangler's output when it fails, for the console to
read. Secrets survive deploys, so a Worker's secrets are set once by hand until they come from sops.

## Credentials

**`CLOUDFLARE_WORKERS_TOKEN`, an account-owned token, is in the platform's sops file and the
deployer's `secret.env` on its node, and never in GitHub.** It carries Workers Scripts Edit and
Connectivity Directory Bind; Workers Routes Edit on the gateway's zones joins it when the gateway
moves. D1, DNS and anything user-level are never granted. **An artifact of a repository the
monoflake organization does not own is fetched with a token of that owner's** --
`GITHUB_ACTIONS_TOKEN_CANMI21`, read access to Actions on `canmi21/web` alone -- picked by the
source's owner, here and in host.

## Admitting a repository

`canmi21/web` is admitted by four switches, each the operator's: its own `deploy.yml` at that exact
path; a `workflow_run` webhook on it to the hook, signed with the same secret; `canmi21/web` in the
sdk's `DEPLOY_SOURCES`; and the repository in each consumer's own sources -- every node's
`DEPLOY_SOURCES` for its images, the deployer's for its Workers, with `WORKER_OWNERS` naming the
Workers it owns.

## Moving a Worker onto it

**One Worker at a time, never two pipelines live for one.** CI starts emitting its artifact; for the
console and the gateway the deployer first runs it dry for a push or two, recorded and deploying
nothing; then the Worker's Git integration is disconnected and its name joins `WORKER_OWNERS`. The
order: the console, then `aka`, `cdn` and `quota`, then the gateway, and the site last, after its
D1 moves to Postgres.

**`hook` stays on Cloudflare's Git integration.** It carries the deployer's own notices, and a hook
the deployer broke the deployer could not mend -- host never updates itself either; keeper does.

**Rolling back** is `wrangler rollback`, any of the last hundred versions, offered as host offers
it. A broken pipeline is mended by reconnecting the Worker's Git integration and removing its name
from `WORKER_OWNERS`, and `wrangler deploy` from the author's machine stays the way in when both
fail.

## Not yet

Previews per branch, a gradual split between two versions, a Worker falling back to a node, secrets
from sops, deleting a Worker, Durable Object and D1 migrations, and more than one Cloudflare account.
