# Issues: what is open

Every open question the platform has: something found and not yet decided. What is decided and
waiting is [../todo/todo.md](../todo/todo.md), and the direction is [../roadmap.md](../roadmap.md);
how the three divide the work is the workspace's `spec/planning.md`, and the questions every project
shares are the workspace's `spec/issues.md`.

An entry says what was found, what the evidence is, and what deciding it would cost, and stops
there. An entry that is decided leaves this list: for the todo if it is work, or for a rule in an
ordinary file if deciding it was all of it. This file is the index; an entry lives in its area's
file.

| area                           | entries | what it holds                                         |
| ------------------------------ | ------- | ----------------------------------------------------- |
| [gateway.md](gateway.md)       | 4       | where the hosts are against the gateway they moved to |
| [relay.md](relay.md)           | 1       | what the relay leaves open                            |
| [scheduling.md](scheduling.md) | 9       | what the schedulers and Postgres leave open           |
| [services.md](services.md)     | 5       | what the services' own files leave open               |

### [gateway.md](gateway.md)

- The CDN and the alias layer still stamp their own lifetimes
- The whitelists are written by hand, and checked against the table only
- A deployment's host is not checked against where the service runs
- A node's private side cannot tell one app from another

### [relay.md](relay.md)

- Which consensus and which gossip

### [scheduling.md](scheduling.md)

- How a Worker at the edge reaches Postgres on the nodes
- The order the site leaves D1
- What runs on one node until the platform's scheduler exists
- How often geo's data is rebuilt
- How long an app keeps what it deleted
- Exports to look at, kept apart from backups
- Backups are in one failure domain
- A timeline's history can go with the WAL around it
- An unreachable backup store holds the job for an hour

### [services.md](services.md)

- Where the telemetry view goes
- A second place shares `checks` with the first
- A picture is served at its id, to whoever holds it, for as long as it is kept
- grok listens only once it is signed in
- A GitHub bot
