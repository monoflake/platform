# Roadmap

Where the platform is going, without the steps. What is decided and waiting is
[todo/todo.md](todo/todo.md), and what is open is [issues/issues.md](issues/issues.md); how the three
divide the work is the workspace's `spec/planning.md`.

- **Every API is reached through one gateway**, whose declarations are the only description of a
  service's routes, limits and lifetimes -- [architecture/gateway.md](architecture/gateway.md). The
  move is done but for its cleanup.
- **A service runs on whichever placement suits it, and fails over to the next** --
  [architecture/services.md](architecture/services.md), "Cloudflare is the one entrance, and that is
  accepted".
- **The service domains each answer a page of their own**, with the platform's names laid over them
  where a host carries both.
- **An app declares what it needs and the platform places it**: N instances and their memory, buckets
  by copies and failure domains, SQLite or Postgres, shared within a scope and isolated between
  scopes -- [architecture/scheduling.md](architecture/scheduling.md). The per-app sidecars of
  [architecture/objects.md](architecture/objects.md) and
  [architecture/databases.md](architecture/databases.md) give way to it.
- **Three core nodes decide, and every node passes it on**: the control messages become one ordered,
  signed log that relays gossip and a returning node catches up on --
  [architecture/relay.md](architecture/relay.md).
- **One console shows every node and the deploy pipeline, served at the edge and live through the
  nearest node** -- [architecture/console.md](architecture/console.md).
- **Apps are deployed through the platform, Workers carrying only their stateless part**: the
  platform deploys an app's Worker and hands it every binding, state coming from its own Postgres,
  buckets, scheduler and WebSocket services on the nodes -- the workspace's
  `spec/architecture/layers.md`, "Cloudflare is under the platform, and an app binds only the
  platform". The site is the first app to move, D1 to Postgres the largest step of it.
