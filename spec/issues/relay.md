# Issues: the relay

What [../architecture/relay.md](../architecture/relay.md) leaves open. The rules over an entry are
the index's; see [issues.md](issues.md).

## Which consensus and which gossip

The core's agreement is a consensus problem and the spreading an anti-entropy one, and neither is to
be written from scratch. Rust has candidates for each -- openraft for the first; chitchat,
Quickwit's scuttlebutt gossip that already compares versions to find who is behind, and foca, a SWIM
implementation, for the second -- and none has been tried here. What each costs on a node with a
gigabyte of memory, and whether one library could do both, is undecided until they are measured.
