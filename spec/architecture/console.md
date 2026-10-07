# Console: every node at once, served at the edge

Where the platform's view of itself is going, and none of it is built. Each node's own panel shows
that node -- infra's `spec/architecture/host.md` -- and keeps working when everything above it is
down; the console is the view of all of them, and of what CI is building, for everyday use.

## The UI is at the edge, the data is the nodes'

**The console is a SvelteKit app rendered on Cloudflare, at the edge**, behind Access, so it is as
near the reader as Cloudflare is, and it holds no data. A page's first paint is rendered by the
Worker from what the nodes answer: the cluster from the nearest relay's `/state`, and a node's own
readings from its host's API, reached through that node's VPC binding at the panel's interface with
the read token. The Worker reads its bindings from `cloudflare:workers`, since SvelteKit's
`event.platform` is empty under its Cloudflare adapter, and runs with `nodejs_compat`, which
SvelteKit's server needs.

**The page and its live socket are one Worker on one host, `console.canmi.app`.** `/live`, `/state`
and `/nearest` are answered in the server hook before any page: the Worker picks the nearest node
from where Cloudflare says the reader is and hands the request to that node's relay by its VPC
binding, the next node when it fails. A response the hook returns itself leaves SvelteKit as it
was made, which a WebSocket's 101 must, and does: a browser saw the 101 on 2026-10-06. One host because Access sets its cookie per concrete
hostname and cannot set one ahead for a wildcard application's subdomains, and a WebSocket cannot
follow Access's redirect to get one: a page on one name could not open a socket on another --
https://developers.cloudflare.com/cloudflare-one/identity/authorization-cookie/.

**It is dark, drawn with semantic names** -- ground, surface, line, text, good, warn, danger and
the series -- that a palette fills: the kit's Nord defines them, and for now the console points the
surfaces, lines and states at the kit's black and white `mono.css`, Nord keeping the series, so the
layout is tuned without color before color comes back. Its charts
are drawn as SVG by the app itself with d3's scales and shapes, so the server renders them whole:
a chart library drawing on a canvas would paint nothing until the browser ran it.

**The shell is three fixed regions, and only the page scrolls.** The sidebar runs down the whole
left edge with its rule, the top bar sits right of it alone, and the page between them is the one
scrolling element; the document itself never scrolls or bounces. Their sizes are in `rem`, so the
three keep their proportions as the reader's text size changes. Rules come in two levels: the
shell's own a step fainter (`--color-line-faint`), the page's cards and tables at `--color-line`. A page says what it is in its
title and the facts beside it -- never a sentence about the page, under it or under a card. Its
`<title>` is the one name the page is about and nothing around it -- `Nodes`, `tyo`, `#123`, an
app's name -- with no product name and no separator: the console is behind Access and indexed by
nobody, so a title is for a reader picking out a tab, and the shortest name does that best. Its
icons are the `console` scope's marks, the API's own, followed for the browser as every page's are.

**Every time is written in the reader's zone**, which Cloudflare names on the request, set once in
the layout and read by every chart, so the server and the browser write the same text and the
page does not change as it wakes; a zone Intl does not know falls back to UTC. **The world map is
projected when the console is built**, flat and as a grid of dots, so neither the Worker nor the
browser carries a projection or a world's topology -- only the dots it drew. A globe is offered
beside it and loaded only when asked for, being WebGL the server cannot draw. On both, a node's mark
says two things: its size how much it runs, in three steps by the apps running on it, and its
opacity how busy it is, in four steps by its CPU now. A node heard in time is one blue; color is
kept for the exceptions, a late node ringed amber and a gone one hollow in red. No line is drawn between nodes;
the marks alone carry the map.

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
