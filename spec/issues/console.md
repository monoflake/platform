# Issues: the console

What [../architecture/console.md](../architecture/console.md) leaves open. The rules over an entry
are the index's; see [issues.md](issues.md).

## Where the console learns a node's facts

A node's tier, failure domain, expiry year and system are infra's, in its `nodes/nodes.toml`, and
the console needs them for the node table and each node's header. Today
`apps/edge/console/src/lib/nodes/facts.ts` copies them by hand, so a node added or retired in infra
leaves the console wrong until somebody edits both. Each node's host could serve its own row, the
relay could carry the table with the snapshots, or the build could read the file from infra; each
moves where the fact is held, and none is chosen.
