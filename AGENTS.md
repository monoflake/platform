# AGENTS.md

What anyone working here reads after the workspace's `AGENTS.md`, whose rules hold here as in every
repository below it; this file adds only what is this repository's own. It holds the platform: its
design, worked out from what an app needs down to what the real world already provides and checked
by a model, and the code that follows the model.

It is public at `monoflake/platform`, listed in the workspace's `repos/registry.toml` as
`monoflake/platform`, beside the private `monoflake/cloud`. No task here deploys the platform itself
or touches another repository; `code/tools/deploy` is what a user runs to deploy an app of their
own, from wherever it lives, RFC n0o4l.

## Start here

Read [docs/method.md](docs/method.md), how work is done here, then the drafts in `docs/rfcs/` your
question touches; to write code, [docs/code.md](docs/code.md) and the block's brief. Decisions are the author's: a block's questions together, the most urgent block
first.

## The tree

```
model/      the spec: graph/, ground/, bootstrap/, names/; contracts/, in subset/, kinds/ and
            records/; plan/, the checklist; checks/, in design/, written/ and layout/
code/       the code, a component placed by its layer: apps/, products/, primitives/, substrate/;
            and libs/, tools/
docs/       what is read: rfcs/, the drafts; lessons/, facts with their sources; method.md;
            scope.md, what the model covers; envelope.md, what the generator writes;
            signed.md, who signs what
tests/      the samples, data alone: codec/, values in both forms; kinds/ and products/, each
            interface's cases; properties/, what only a history shows; cbor/, a standard's own;
            compat/, the versions' cases; keys/, placement/ and layout/, computed apart
vendor/     other projects' files, copied at one version and left as written
```

- **What a user runs is here, MIT OR Apache-2.0; what runs it as the hosted platform is not**:
  the platform half and the hosted platform's configuration are the private `monoflake/cloud`'s, RFC
  fhg6w. Here the platform half is two roles, `authority` and
  `directory`, known by the edges this half has into them; cloud fills them, proves those edges
  carried, and its `mise run check` is the whole model, RFC 8lkuv.
- **The drivers are `monoflake/driver`'s**: here `driver(machine)` and `driver(cloudflare)` are
  roles, asked in `model/ground/drivers.res` and filled by that repository's model, RFC 7ykg6.
- **The model is the spec**: what a draft decides is written once in `model/`, and the draft keeps
  why. `model/contracts.json` is what every language reads.
- **A script in `scripts/` decides only order**; one that begins to compute hands that part to a
  tool in `code/tools/`.
- **The root's workspaces take what `code/` holds**: `Cargo.toml` lists every crate and
  `pnpm-workspace.yaml` takes `code/**`, while the root's `rescript.json` and `package.json` list
  no block, since each builds alone, [docs/code.md](docs/code.md); the check holds all four.

## Commands

The model is ReScript; the tasks are mise's, the tools the workspace's. What it inherits from the
workspace -- `.editorconfig`, `.oxfmtrc.json`, `.oxlintrc.json`, `rustfmt.toml`, `jujutsu.toml` --
sits at the root as a link up to the workspace's file, which dangles in a clone of this repository
alone.

| Command                          | Does                                                             |
| -------------------------------- | ---------------------------------------------------------------- |
| `mise run prepare`               | once in a clone: installed, compiled, generated                  |
| `mise run generate`              | the ReScript a tool writes of a library, again                   |
| `mise run check`                 | compiles the model and runs `model/check.res`                    |
| `mise run check --ready`         | asks whether building may begin                                  |
| `mise run check --write`         | writes `model/contracts.json` again from the model               |
| `mise run fmt`                   | formats the ReScript, the prose and the JSON                     |
| `mise run verify`                | everything formatted, the check, the blocks, the deny            |
| `mise run brief <name>`          | one block's brief, read from the model                           |
| `mise run accept <name>`         | one block held to its brief, alone                               |
| `mise run built <name>`          | one block built, formatted, linted and tested alone              |
| `mise run blocks`                | every written block built alone, as verify asks                  |
| `mise run deploy <app> <target>` | an app built by wrangler and run on a test machine, RFC n0o4l    |
| `mise run conform <target>`      | the kinds' samples run on a test machine's driver, RFC n0o4l     |
| `mise run lose <target>`         | a test machine's driver stopped while hello is asked, RFC rmll5  |
| `mise run replace <target>`      | a test machine's driver and entry replaced under load, RFC ehm48 |

A commit waits on `mise run check monoflake`, run from the workspace: this verify, then the
workspace's rules over the tree.
