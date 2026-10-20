# AGENTS.md

What anyone working here reads after the workspace's `AGENTS.md`, whose rules hold here as in every
repository below it; this file adds only what is the blueprint's own. The blueprint is the paper
model of the platform's next architecture: the design worked out from what an app needs down to
what the real world already provides, checked by a model, before any of it is built.

It is public at `monoflake/platform`, listed in the workspace's `repos/registry.toml` as
`monoflake`. Nothing here deploys anything or touches another repository.

## Start here

Read [docs/method.md](docs/method.md), how work is done here, then the drafts in `docs/rfcs/` your
question touches. Decisions are the author's: one question at a time, the most urgent first.

## The tree

```
model/      the spec: graph/, ground/, bootstrap/, names/; contracts/, in subset/, kinds/ and
            records/; plan/, the checklist; checks/, in design/, written/ and layout/
code/       the code, a component placed by its layer: apps/, products/, primitives/, substrate/,
            platform/; and libs/, tools/
docs/       what is read: rfcs/, the drafts; lessons/, facts with their sources; method.md;
            scope.md, what the model covers
tests/      the samples, data alone: codec/, values in both forms; kinds/, each interface's cases;
            properties/, what only a history shows
scripts/    the entries that drive the rest, in order: no logic of their own
vendor/     other projects' files, copied at one version and left as written
```

- **The model is the spec**: what a draft decides is written once in `model/`, and the draft keeps
  why. `model/contracts.json` is what every language reads.
- **A script in `scripts/` decides only order**; one that begins to compute hands that part to a
  tool in `code/tools/`.
- **The root's three workspaces list what `code/` holds**: `Cargo.toml`, `package.json` with
  `pnpm-workspace.yaml`, and `rescript.json`, each list held to it by the check.

## Commands

The model is ReScript; the tasks are mise's, the tools the workspace's.

| Command                  | Does                                                  |
| ------------------------ | ----------------------------------------------------- |
| `pnpm install`           | once, the ReScript compiler                           |
| `mise run check`         | compiles the model and runs `model/check.res`         |
| `mise run check --ready` | asks whether building may begin                       |
| `mise run check --write` | writes `model/contracts.json` again from the model    |
| `mise run fmt`           | formats the ReScript, the prose and the JSON          |
| `mise run verify`        | everything formatted, the check, and the crates' deny |

A commit waits on `mise run check monoflake`, run from the workspace: this verify, then the
workspace's rules over the tree.
