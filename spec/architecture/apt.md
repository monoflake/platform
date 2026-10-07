# `apt`: the machine's own packages, through a narrow door

The node's operating system updates its packages as any Debian machine does, with `apt-get`, as
root, from systemd units on the machine. `apps/system/apt` is how the platform asks for that without being
root: a small service that can start two fixed systemd units and read how they went, and nothing
else. It is the pattern for any privilege the platform needs from the machine -- a proxy that holds
the privilege, and a door narrow enough that holding the door is not holding the privilege.
It is Debian's agent behind the interface every node's package manager answers, and Alpine's is
`apk` -- [packages.md](packages.md).

## The work stays on the machine, in two units

**What runs is two systemd services on the machine, `apt-nightly-update.service` and
`apt-weekly-upgrade.service`**: the first `apt-get update`; the second `update`, `full-upgrade`,
`autoremove --purge` and `clean`, then a note when a newer kernel waits for a reboot. Their unit
files are kept in `apps/system/apt/units/` and installed by infra's `mise run node`, since host has
no business writing the operating system's configuration. When they run is `cron`'s, per
[cron.md](cron.md): the update daily, the upgrade weekly and spread across the nodes, a day apart.

**Every Debian node runs `apt`, and nothing else updates it.** The same task stops Debian's own
`apt-daily` timers and removes `unattended-upgrades` where an image shipped it, so a node's packages
change only in a run the ledger records.

## The door

**`apt` answers on a Unix socket, `apt.sock` in its directory, and on no port**: only what the
socket is mounted into can ask, which is `cron` alone, so it needs no token. The socket is made
writable by anyone, since `apt` runs as root and `cron` does not: the mount is the door, not the
file's mode.

| Route                | Answer                                                                                                                                      |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `GET /health`        | the envelope's success, once systemd answers                                                                                                |
| `GET /status`        | each job -- `update`, `upgrade` -- its unit, whether it is running, and its last run: when it started and ended, its result and exit status |
| `POST /jobs/update`  | starts the update unit and answers `202` with the job's state; `409` while it is already running                                            |
| `POST /jobs/upgrade` | the same for the upgrade unit                                                                                                               |

**No request carries anything that becomes part of a command.** The two unit names are constants in
the code; a path names a job, and a job is one of two words. Every answer is the envelope,
[services.md](services.md), "Every answer is one envelope".

**It starts a unit through systemd's D-Bus API, and reads its properties the same way**: the
machine's system bus socket is the one thing mounted from the machine, and the container runs as
root only so systemd lets it start a unit. It has no capability beyond that, a read-only root, and
its own network, used for nothing but telling the ledger. The bus could start any unit; the code
starts two, and that is where the narrowing is.

**Every run is a ledger task**, `apt`'s own, kind `update` or `upgrade`, its parent the `cron` run
that asked (`X-Task-Parent`), with events as the unit starts and ends and the result and exit
status on the last. A run is followed by watching the unit's properties until it is no longer
active.
