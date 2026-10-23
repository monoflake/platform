---
name: 'Names Inside the System'
title: "The project's own name taken out of everything inside the system, and a check that keeps it out"
status: accepted
supersedes: []
blocked-by: [54q45]
commits: []
references: []
---

## Question

The workspace's `docs/naming.md` lets the project's own name appear only where a datum leaves the
system and meets other people's. The threads from RFC n0o4l to 54q45 spelled it in units, options,
paths, a bridge, container labels, Docker objects and temporary names, since no check held the
rule. What is each called instead, and what keeps the rule from now on.

## Decision

Decided by the author on 2026-10-23, the names proposed by the dispatcher and taken.

| Was                                                       | Is                                                   |
| --------------------------------------------------------- | ---------------------------------------------------- |
| units `monoflake-driver`, `monoflake-entry`               | `driver-machine`, `driver-machine-entry`             |
| unit `monoflake-tunnel`                                   | `tunnel`                                             |
| options `monoflake.driver.*`, `monoflake.tunnel.*`        | `machine.driver.*`, `machine.tunnel.*`               |
| `/var/lib/monoflake/{driver,dev,artifacts}`               | `/var/lib/driver-machine/{state,dev,artifacts}`      |
| `/run/monoflake/...`                                      | `/run/tunnel`, and each unit's own runtime directory |
| bridge `monoflake0`                                       | `driver0`                                            |
| container labels `monoflake.*`                            | `driver.*`                                           |
| Docker `monoflake-builder`, `monoflake-local` and volumes | `machine-builder`, `machine-local`                   |
| temporary names `monoflake-<tool>-`                       | `<tool>-`                                            |

- **The platform a machine belongs to is one configured value**, an option of the machine's own
  that code reads where it needs the name, never a spelling in code.
- **Nothing is migrated**: the platform keeps no data, so what the old names made is removed and
  made again under the new, hello deployed again.
- **The rule is checked**: the workspace's names part refuses an owner the registry lists, spelled
  in a repository's code, outside a manifest's name, a published address and a format a module
  declares, `model/rules/naming.res`'s `own-name` held by it rather than `Pending`.
- **Acceptance**: `conform`, `lose` and `replace` pass on the local machine, buf and sin under the new
  names, and the check finds no own name left.
