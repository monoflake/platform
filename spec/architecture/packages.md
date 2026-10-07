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
and a third package manager is a third agent that answers the same table. **Every node runs the one
agent its system has, beside its own `cron`** -- [cron.md](cron.md) -- each granted its role by the
node, infra's `spec/architecture/host.md`, "A role is asked for by the app and granted by the node".

## The agents

- **`apt`** drives two systemd units that run `apt-get` -- [apt.md](apt.md).
- **`apk`**, for Alpine, drives `apk` under OpenRC on the same terms: the work stays on the machine,
  the agent holds the privilege, and its door is a Unix socket only the scheduler is given. It is not
  built yet; how it is to be built is below.

## `apk` reaches the machine through a named pipe

Alpine has no systemd and no D-Bus, so there is no bus to start a fixed unit over. **The machine
runs a door of its own instead: one OpenRC service, kept up by `supervise-daemon`, reading words from
a named pipe and running one of two fixed jobs.**

- **The jobs are the machine's.** `update` is `apk update`; `upgrade` is `apk update` and
  `apk upgrade --available`, each with `--wait` for apk's lock, then the reboot check below. Any
  other word is dropped, so nothing the container writes becomes part of a command. One job runs at a
  time, under `flock`, and its output goes to the system log.
- **Each job's state is a file the door writes and the agent reads**: running or not, when it
  started and ended, its exit status, whether a reboot waits, and a counter that moves with every
  run. It is written to a temporary file and renamed, so it is never read half-written, and it lives
  on disk, so the last run outlasts a reboot. A state still running when the door starts is
  rewritten as failed, interrupted.
- **The container holds the pipe's directory, read-only, and nothing else of the machine.** It
  writes a word into the pipe and reads the state files back. The directory, not the files, is
  mounted, so a renamed file shows through. A door that is not reading makes the pipe refuse to
  open, which the agent answers as unavailable rather than waiting.
- **The door starts before Docker**, since Docker refuses to start a container whose mount has no
  source. infra's `mise run node` installs it on an Alpine node, as it installs `apt`'s units on a
  Debian one.
- **A newer kernel waiting** is the running kernel's modules gone: Alpine keeps one kernel package
  and replaces its modules directory on upgrade, so `/lib/modules/$(uname -r)` missing means a
  reboot waits.

**host's `steward` role mounts whichever door the machine has**: the system bus socket where there
is one, the door's directory where there is that, and refuses to start the steward with neither.
The role stays one word and host knows no system by name. **`apt` and `apk` share one library**
for the routes, the ledger and following a run, behind a driver each implements, and stay two
binaries, so `apk` carries no D-Bus.

Decided on 2026-10-07. Rejected: a privileged container entering the machine's namespaces, which
holds all of root to run two commands.
