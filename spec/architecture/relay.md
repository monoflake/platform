# Relay: three nodes decide, every node passes it on

Where the platform's control messages are going, and none of it is built. Today a finished run
reaches nodes as one notice per node, sent once by `hook` -- [services.md](services.md), "Every node
is the same node"; a node that was away then never hears of it.

## Three nodes agree, and the rest pass it on

**Three core nodes, one per failure domain, decide what happened: `rdu`, `buf` and `tyo`.** A
message is committed once two of the three have confirmed it, and committed messages form one log,
numbered in order and never rewritten. The nodes and their domains are infra's
`spec/architecture/nodes.md`, "Three nodes are the core, named by the author"; three in three
domains survive the loss of any one account.

**Every other node is a relay.** It keeps the log, and passes it on to whoever asks. A node does not
care where it heard a message: it compares how far its log goes with a neighbor's and takes what it
lacks. One number says whether a node is behind, because the log is in one order -- which is what
deciding among three first buys.

**A committed entry is signed by the core**, so a relay can carry it and cannot forge it. Any node
taken over can withhold messages, never invent one.

**A node that was away catches up by the same comparison**, from whichever neighbor it reaches
first, which is what makes a node allowed to go offline -- `home` -- whole again when it returns.

## What travels on it

A run that finished is the first message: `hook` hands it to the core instead of to every node. What
a run built can follow the same way: GitHub records each artifact's digest, so a node can take the
bytes from a neighbor and check them, and a node without IPv4 then needs nothing from GitHub.

## The live half is built first

**`apps/system/relay` runs on every node, as a peer** -- infra's `spec/architecture/host.md`, "A role
is asked for by the app and granted by the node" -- on port 12012, its port open to the other
nodes over the tailnet and host's own network open to it. Every three seconds it reads its node's
host with the read token: the events, the apps, the machine's readings. That is the node's
snapshot, and the node is the only authority on it: a neighbor's word on a node's own snapshot is
never taken.

**A snapshot's version is its origin's clock, in milliseconds**, or one past the last where the
clock has not moved, so a relay that restarts starts above whatever its neighbors still hold and
keeps nothing on disk. Comparing versions is the whole of "is this behind".

**A relay pushes its own snapshot when it changes, and passes the others on by comparison.** Every
two seconds each tells its neighbors which versions it holds, and each answers with what the other
lacks. Flooding every snapshot on arrival would carry each about seventy times across a full mesh
of seven every three seconds; comparing costs a hop up to two seconds instead. A node that cannot
reach a third directly still hears it through a neighbor.

**The mesh is `/mesh`, a WebSocket each relay dials on every other**, admitted by a secret the
relays share, `RELAY_SECRET`. The peers are one value every node is given alike, `RELAY_PEERS`,
`name=address:port` by tailnet address, a relay skipping its own. Each stream's first message
carries the contract's version, and a neighbor speaking another is dropped. Both ends ping every
three seconds -- the round trip below -- and drop a socket silent for ninety, and redial from one
second, doubling to a minute. A browser's socket is pinged every thirty.

**A browser opens `/live` on `relay.canmi.app`**, behind Access, and is sent the whole cluster, then
every change; `/state` answers the same once, for the console's polling. **`/live` admits a page on `.app`
alone**, by its `Origin`: Access lets a reader in by a cookie the browser sends on any page's
WebSocket, so without the check any site the reader visits could open it as them. A request with no
`Origin` comes from no browser and carries no reader's cookie, and passes; the private mirror's
pages are refused, since the console is served on `.app`. Each node's entry carries
`heard_at`, when this relay last took a newer version of it: a live node moves about every three
seconds, so an old `heard_at` means the node, or every path to it, is down.

## The console asks, and the relay answers from memory

**Every read the console's server makes of a relay is answered at once, from what the relay already
holds.** The console's server is a stateless front end that draws and never waits -- web's
`spec/architecture/console.md`, "The console's server never waits on data; it only draws" -- and the
relay of the node nearest it is its backend: `/state` is the whole cluster as held, with no read of
host or of a neighbor on the way. A read the console needs that the relay cannot yet answer that way
is held by the relay before the console reads it, never gathered while the console waits; what is
still gathered in the console is listed in web's `spec/todo/todo.md`, "The console's reads move to
the backend". Decided with the author on 2026-10-09.

## The runs, mirrored on every relay's disk

**Every relay keeps a mirror of every node's deploy rows of the last 30 days, in a SQLite file of
its own**, so the console's runs -- the overview's deploys, what happened, what failed, Deployments
-- are one read of the nearest relay, answered from its disk. A row is host's event row as
`host.rs`'s `Event` carries it, tagged with the node it happened on. Rows have one writer each: a
node's rows are its host's, read by its own relay and by no other, so the mirror needs no leader and
no agreement -- each origin's rows are compared by version and the newer kept, as a snapshot is. The
mirror is never the record: host's `history.db` is, keeps every row and is what a backup takes. A
mirror lost or corrupted is rebuilt from the relay's own host and from its neighbors, so it is never
backed up. Decided with the author on 2026-10-09.

- **A row's version is its origin relay's clock, in milliseconds**, given when that relay first
  reads the row or reads it changed -- a deploy moves through its stages -- and one past the
  origin's last where the clock has not moved, as a snapshot's version is.
- **What changed in the last three minutes is held in memory, the window**, and spread on the mesh
  as snapshots are: pushed by its origin, compared and passed on by the rest. A neighbor behind by
  more than the window is answered from the disk, by origin and above the version it holds.
- **The window is written to disk every 30 seconds, six chances a row inside it**: a write that
  succeeds marks what it took as written and the next chances leave it be; a row leaves memory once
  it is written and older than the window, never before, so a disk that refuses five writes in a row
  loses nothing, and a refusal is logged with the part, as a host read's is.
- **Rows older than 30 days are dropped, and at most 5,000 a node are kept**, the oldest going
  first; the drop runs with a write.
- **On start a relay reads its file, then its host's rows back to 30 days** by host's own
  paging, `/api/events?limit=50&before=<id>`, stopping at a row past 30 days, a short page or 5,000
  rows, and asks its neighbors for every origin above the version its file holds; the live half
  waits on neither, since no neighbor is ever asked for a relay's own rows. A page host does not
  answer is asked again 30 seconds later.
- **A file that cannot be opened is moved aside, never mended**: renamed with the time beside it,
  logged, and a fresh one opened, which host and the neighbors refill; the relay stops only where
  even that fails.
- **`/runs` answers the mirror and the window together**, every node's rows of the last 30 days,
  newest first, each with its node; the console groups them into runs for display -- web's
  `spec/architecture/console.md`, "The console's server never waits on data; it only draws".
- **The file is `/data/runs.db`**, `[data]` in `service.toml`, so the relay is rolled out as an app
  with state on its node is -- infra's `spec/architecture/host.md`, "An app chooses how it is rolled
  out, and keeping nothing earns a gapless one".

## The round trip to each neighbor

**A relay times its own pings on `/mesh`, and its snapshot carries the latest per neighbor as
`round_trip`**: `{ "tyo": 0.1512, "buf": 0.0184 }`, by node, in seconds to a tenth of a millisecond. It travels
as the rest of the snapshot does, to every relay and to `/live` and `/state`, so a page reads each
node's round trip to every other from that node's own entry. Asked for on 2026-10-09, for the
console's row of each node's round trip to the database's primary.

- **The WebSocket's own ping is timed, not a message of the mesh's.** The other end's socket
  answers it beneath the relay with a pong carrying the ping's payload back, and the payload is
  when the ping was sent, so nothing is kept per ping and a late pong still times its own. A
  relay of an older build answers it the same, and the mesh's messages and contract are untouched.
  What it measures is the relays' own path over the tailnet, a busy peer's queue included; an
  app's connection to another node's port takes the same path but not the same queue.
- **Every three seconds, on every socket, the first as the socket opens** -- the same `own::EVERY`
  the snapshot is taken at, since a faster ping times a figure no snapshot carries and a slower one
  leaves the figure a round behind. A ping and its pong are two frames of a few bytes, beside the
  kilobytes of snapshot each socket carries every round. Both sockets between two relays time it,
  and the latest of either stands.
- **A neighbor not timed within three pings is absent**, never `null` or a last figure held on --
  the workspace's `spec/json.md`, "Absent, not null" -- and with none timed the key itself is
  absent, as `stale` is. A relay never times itself, so a node's own name is never a key.
- **Seconds, as the workspace's `spec/json.md` has every duration**, and the page says them in
  milliseconds: what is written for a machine follows the one rule, and what is shown to a reader
  is the page's own wrapping of it, as a node's code is wrapped in its city. It was `round_trip_ms`
  for its first hours on 2026-10-09 and was renamed before anything but the console read it. A changed round trip is
  a changed snapshot, a new version, as a changed machine sample already is every round.
- **No contract bump**: an added optional key is not a schema change -- `spec/json.md`, "An optional
  key is not a schema change" -- and a relay carries a snapshot as the JSON its node wrote.

## The order it is built in

1. **A port on the tailnet**: host's `peer` role, which the live half above runs in.
2. **The log, with one writer.** `hook` writes to one core node, and every node gossips the log and
   catches up by it. A node that was away no longer misses a run.
3. **Three writers.** The one writer becomes the three, an entry committed by two of them.

Which consensus and which gossip is open -- [../issues/relay.md](../issues/relay.md).
