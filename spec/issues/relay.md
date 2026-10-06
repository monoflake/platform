# Issues: the relay

What [../architecture/relay.md](../architecture/relay.md) leaves open. The rules over an entry are
the index's; see [issues.md](issues.md).

## Which consensus and which gossip

The core's agreement is a consensus problem and the spreading an anti-entropy one, and neither is to
be written from scratch. Rust has candidates for each -- openraft for the first; chitchat,
Quickwit's scuttlebutt gossip that already compares versions to find who is behind, and foca, a SWIM
implementation, for the second -- and none has been tried here. What each costs on a node with a
gigabyte of memory, and whether one library could do both, is undecided until they are measured.

## How a browser reaches its nearest node

The console's live view holds a WebSocket to the nearest node -- [../architecture/console.md](../architecture/console.md).
Either the gateway picks the node from where Cloudflare says the reader is and passes the socket on
over that node's VPC binding, which needs Workers VPC to carry a WebSocket, unverified; or each node
answers on a name of its own through its tunnel and the UI picks one. Which is undecided until the
first is tried.
