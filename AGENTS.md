# AGENTS.md

The entry point for anyone starting here with no context. The blueprint is the paper model of the
platform's next architecture: the design worked out from what an app needs down to what the real
world already provides, checked by a model, before any of it is built. It is the author's new
attempt, and the workspace above it is to be rebuilt on what it settles, so a rule of the
workspace's is never a reason here; its tools are borrowed only where nothing conflicts.

It is local only: no remote, not in the workspace's `repos.toml`, never pushed until the design
lands, so nothing here deploys anything or touches another repository.

## Start here

Read [docs/method.md](docs/method.md), how work is done here, then the drafts in `docs/rfcs/` your
question touches. Decisions are the author's: one question at a time, the most urgent first.

## The tree

```
model/      the spec: the graph, the ground, the bootstrap path, the contracts, and the checks
code/       the code, a component placed by its layer: apps/, products/, primitives/, substrate/,
            platform/; and libs/, tools/
docs/       what is read: rfcs/, the drafts; lessons/, facts with their sources; method.md;
            scope.md, what the model covers
vendor/     other projects' files, copied at one version and left as written
```

- **The model is the spec**: what a draft decides is written once in `model/`, and the draft keeps
  why. `model/contracts.json` is what every language reads.
- **No directory holds more than 16 entries or lies more than 5 deep**, from a top-level directory
  or a package's root; the check holds both.

## Commands

The model is ReScript; the tasks are mise's, the tools the workspace's.

| Command                  | Does                                                      |
| ------------------------ | --------------------------------------------------------- |
| `pnpm install`           | once, the ReScript compiler                               |
| `mise run check`         | compiles the model and runs `model/check.res`             |
| `mise run check --ready` | asks whether building may begin                           |
| `mise run check --write` | writes `model/contracts.json` again from the model        |
| `mise run fmt`           | formats the ReScript, the prose and the JSON              |
| `mise run verify`        | what a commit passes: everything formatted, and the check |

A commit is made only after `mise run verify` passes.
