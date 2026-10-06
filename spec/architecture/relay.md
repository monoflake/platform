# Relay: three nodes decide, every node passes it on

Where the platform's control messages are going, and none of it is built. Today a finished run
reaches nodes as one notice per node, sent once by `hook` -- [services.md](services.md), "Every node
is the same node"; a node that was away then never hears of it.

## Three nodes agree, and the rest pass it on

**Three core nodes, one per failure domain, decide what happened: `tyo`, `buf` and `gvx`.** A
message is committed once two of the three have confirmed it, and committed messages form one log,
numbered in order and never rewritten. The nodes and their domains are infra's
`spec/architecture/nodes.md`; three in three domains survive the loss of any one account.

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
thirty seconds and drop a socket silent for ninety, and redial from one second, doubling to a
minute.

**A browser opens `/live` on `relay.canmi.app`**, behind Access, and is sent the whole cluster, then
every change; `/state` answers the same once, for the console's polling. Each node's entry carries
`heard_at`, when this relay last took a newer version of it: a live node moves about every three
seconds, so an old `heard_at` means the node, or every path to it, is down.

## The order it is built in

1. **A port on the tailnet**: host's `peer` role, which the live half above runs in.
2. **The log, with one writer.** `hook` writes to one core node, and every node gossips the log and
   catches up by it. A node that was away no longer misses a run.
3. **Three writers.** The one writer becomes the three, an entry committed by two of them.

Which consensus and which gossip is open -- [../issues/relay.md](../issues/relay.md).
