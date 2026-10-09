# Issues: the relay

What [../architecture/relay.md](../architecture/relay.md) leaves open. The rules over an entry are
the index's; see [issues.md](issues.md).

## Which consensus and which gossip

The core's agreement is a consensus problem and the spreading an anti-entropy one, and neither is to
be written from scratch. Rust has candidates for each -- openraft for the first; chitchat,
Quickwit's scuttlebutt gossip that already compares versions to find who is behind, and foca, a SWIM
implementation, for the second -- and none has been tried here. What each costs on a node with a
gigabyte of memory, and whether one library could do both, is undecided until they are measured.

## What the relay holds for the console

The console's runs -- the overview's deploys in the last day and how long one takes, what happened,
what failed, Deployments -- are gathered in the console's Worker from every node's last 500 events,
which the rule in [../architecture/relay.md](../architecture/relay.md), "The console asks, and the
relay answers from memory", forbids. The proposal: each relay reads its own host's deploy events
over a longer window than the snapshot's 50 rows -- the last 30 days -- and holds them compacted to
one record a run and an app on that node, carried on the mesh as a part of its own, versioned as a
snapshot is and changing only when a deploy moves; any relay then answers the cluster's runs,
grouped across the nodes, in one read. Undecided: the window, 30 days or a count; whether the runs
travel inside the snapshot or beside it, since they change far less often than the machine's
readings; and whether the relay answers the grouped runs, the console summarizing them for display,
or the summaries themselves. The fleet's readings for Nodes and the database's primary follow once
this is settled.
