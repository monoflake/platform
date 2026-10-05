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
