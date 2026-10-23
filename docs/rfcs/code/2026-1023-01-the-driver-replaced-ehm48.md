---
name: 'The Driver Replaced'
title: 'The third thread: the driver and the entry replaced, and a machine switched, while hello serves'
status: accepted
supersedes: []
blocked-by: [rmll5]
commits: []
references: []
---

## Question

RFC rmll5 made the entry a process of its own, so a driver stopped leaves hello serving. A new
build still restarts the entry, since one binary runs both, and a switch restarts what its units
changed; and the binary, copied by `dev`, and the module, switched by `switch`, move apart, so a
change in what the module passes the binary has twice brought a unit down until the other came. How
is a machine's driver replaced with no request refused, and the binary and the module moved as one.

## Decision

Decided by the author on 2026-10-23, the steps proposed by the dispatcher and taken.

- **Replacing is a command that can fail**, `mise run replace <target>`: while hello is asked through
  the entry and the tunnel many times a second, it restarts the driver, the entry and containerd,
  and copies a new build, and reports every request refused or failed and the longest gap.
- **The entry is restarted without refusing**: its listening socket is held by a socket unit, so a
  connection waits through the restart rather than being refused, and a process stopping answers
  what it has begun before it exits.
- **The binary and the module move as one** where a change needs both: `switch --driver` builds the
  binary as `dev` does, puts it in the store, and the module runs it by that store path, so one
  switch moves both and a generation rolled back takes both back. `dev` stays the loop for a change
  of the binary alone.

| Step | What                                                          | Where           | Done when                                                        |
| ---- | ------------------------------------------------------------- | --------------- | ---------------------------------------------------------------- |
| 1    | `replace`, run once as things stand                           | platform        | its report shows what each restart refuses now                   |
| 2    | The entry's socket held across its restart, in-flight drained | driver, machine | `replace` finds no request refused or failed through either path |
| 3    | `switch --driver`, the binary by its store path               | cloud, machine  | a flag added and removed rolls out in one switch with no failure |
