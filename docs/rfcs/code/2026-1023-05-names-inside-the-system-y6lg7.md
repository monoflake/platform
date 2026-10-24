---
name: 'Names Inside the System'
title: "The project's own name taken out of everything inside the system, and a check that keeps it out"
status: landed
supersedes: []
blocked-by: [54q45]
commits:
  [
    monoflake/machine@6469e27b,
    monoflake/driver@b1af0fc8,
    monoflake/platform@7b1fb61e,
    monoflake/cloud@0c4e8225,
    monoflake/runtime@698e9b23,
  ]
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
- **Acceptance**: `conform`, `lose` and `replace` pass on the local machine and both test machines under the new
  names, and the check finds no own name left.

### Ledger

Choices made provisionally while the thread ran, for the author to read.

- **Names the table left open**: `/etc/driver-machine/images`, `/run/driver-machine/secrets`, the
  local binding's token at `/var/lib/driver-machine/binding`, the local units `local-disk` and
  `local-binding`, the image `machine-empty:1`, the temporary names `ssh-` and `switch-`, and
  conform's instance unit `conform`, the unit `tunnel-address`, the volumes `machine-local-nix`
  and `machine-local-state`, and ssh's connection sockets `~/.ssh/deploy-%C` and `~/.ssh/dev-%C`,
  generic names in a directory other tools share, each told apart by its connection's hash.
- **`MONOFLAKE_FILL` is `FILL`**, the variable the platform's model reads from its two halves.
- **The layout vectors' seeds lost the name**, `layout sample` and its siblings, and the vectors were
  made again by a reference written from RFC b8f35 alone, which first reproduced the old ones; the
  reference was not kept, so the vectors stand on the library's tests passing against them.
- **Kept, and declared under `[[names.data]]`**: the `typ` values and key contexts, the reserved
  name, `monoflake-challenge`, the user-agent `monoflake-runtime`, and the variables a user's code
  reads beside other vendors', `MONOFLAKE_FOOTING` and the secret prefix `MONOFLAKE_`.
- **The machine's platform option is not added** until code reads it, the workspace's deferred item
  `machine-platform`.
- **The check's edges**, the workspace's commit 2a8b8419: the author's own account, a person's name, is outside the rule; comments
  are read; each file repeating a format's data is declared; a `workspace.toml`'s `ids` and
  `spelled` lines pass.
- **hello was down for a few minutes on each machine** while it was switched, since nothing was
  migrated; no request failed in the rehearsals after.
- **The review at the thread's end**, by an agent reading only the commits and the rules, found the
  rename whole and spelled alike in every writer and reader, and the check too loose: a sibling's
  name inside a path, a domain followed by a dot, any dotted host before a path, and a bare name
  declared each let the name through. The workspace's commit 307cf15c closes each, with a test.
  It also found `FILL` generic, kept since it is read only by the model's own tools.
