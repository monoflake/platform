# Packages: one interface to a node's package manager

A node is Debian or Alpine -- infra's `spec/architecture/nodes.md` -- and each keeps its system
current with its own package manager, `apt` on the one and `apk` on the other. The platform asks for
that the same way on both: **one interface, with an agent per package manager behind it.**

## The interface is the layer

**What the platform reaches is a node's package manager, never `apt` or `apk` by name.** Both agents
answer the same routes, in the same envelope, and record their runs as the same ledger tasks, so a
job that updates a node is written once and reaches whichever agent the node runs:

| Route                | Answer                                                                     |
| -------------------- | -------------------------------------------------------------------------- |
| `GET /health`        | the envelope's success, once the agent can reach what it drives            |
| `GET /status`        | each job -- `update`, `upgrade` -- whether it is running, and its last run |
| `POST /jobs/update`  | refreshes what the package manager knows is available; `409` while running |
| `POST /jobs/upgrade` | installs it, then notes when a newer kernel waits for a reboot             |

The interface is a contract and not a process: nothing stands between the scheduler and the agent,
and a third package manager is a third agent that answers the same table. A node runs the one agent
its system has.

## The agents

- **`apt`** drives two systemd units that run `apt-get` -- [apt.md](apt.md).
- **`apk`**, for Alpine, drives `apk` under OpenRC on the same terms: the work stays on the machine,
  the agent holds the privilege, and its door is a Unix socket only the scheduler is given. It is not
  built yet.
