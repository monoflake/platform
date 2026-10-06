# Console: every node at once, served at the edge

Where the platform's view of itself is going, and none of it is built. Each node's own panel shows
that node -- infra's `spec/architecture/host.md` -- and keeps working when everything above it is
down; the console is the view of all of them, and of what CI is building, for everyday use.

## The UI is at the edge, the data is the nodes'

**The console's UI is static and served by Cloudflare**, behind Access, so it is as near the reader
as Cloudflare is. It holds no data. What it shows it asks the nodes for, through the gateway, which
reaches each node's panel by that node's VPC binding.

**The page and its live socket are one Worker on one host, `console.canmi.app`**: the page from
static assets, and `/live`, `/state` and `/nearest` from the Worker's script, which picks the
nearest node from where Cloudflare says the reader is and hands the request to that node's relay
by its VPC binding, the next node when it fails. One host because Access sets its cookie per
concrete hostname and cannot set one ahead for a wildcard application's subdomains, and a
WebSocket cannot follow Access's redirect to get one: a page on one name could not open a socket
on another -- https://developers.cloudflare.com/cloudflare-one/identity/authorization-cookie/.

**It reads, and does not write, at first.** Each node's host gains a read-only token, good for its
`GET` routes alone, and that is the token the console's path carries; a host token is root on its
machine, and seven of them in one Worker would make the Worker root on all seven. Restarting,
deploying and rolling back stay on each node's own panel until writes have a path of their own.

**It depends on the platform and the panel does not**, which is the arrangement the workspace's
`spec/architecture/layers.md` allows: a layer below may lean on one above where it works without
it.

## Live, through the nearest node

**A reader's browser holds one WebSocket, to the node nearest it, and the nodes hold connections to
each other**, so whichever node a reader reached has everything as it happens. That is the relay's
mesh carrying live state beside its log -- [relay.md](relay.md) -- and it needs what the relay's
first step needs, a port on the tailnet. **Workers VPC carries the WebSocket**: the console's Worker
hands the upgrade to the nearest node's binding and gets the relay's 101 back, seen from a browser
on 2026-10-06. While the socket is down the page polls `/state`.

## The pipeline

**What CI is building, what it built, and where each node is with it** are one view: a run queued,
building, built or failed on GitHub; then on each node, the artifact downloaded, loaded, started,
checked healthy, or failed at one of those, or skipped for its architecture or its placements. The
GitHub half comes from `hook`, which receives every run's events and today drops all but a
successful completion; the node half from host, which records each stage as it happens.
