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
| [gateway.md](gateway.md)       | 3       | where the hosts are against the gateway they moved to |
| [scheduling.md](scheduling.md) | 2       | what placing by need leaves open                      |
| [services.md](services.md)     | 4       | what the services' own files leave open               |

### [gateway.md](gateway.md)

- The CDN and the alias layer still stamp their own lifetimes
- The whitelists are written by hand, and checked against the table only
- A deployment's host is not checked against where the service runs

### [scheduling.md](scheduling.md)

- How a copy at home is weighed against a copy at a provider
- A browser sends no header for what a page embeds

### [services.md](services.md)

- Where the telemetry view goes
- A second place shares `checks` with the first
- A picture is served at its id, to whoever holds it, for as long as it is kept
- grok listens only once it is signed in
