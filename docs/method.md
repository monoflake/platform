# Process

How the design is worked out, agreed with the author on 2026-10-15. The old platform was built a
step at a time without a design that held together in theory, and could not carry a stable app; this
one is made to hold together on paper first.

## Five phases, in order

A phase is a step of this work; a stage, `s0`, is how far the model reaches, `docs/scope.md`. The two
words are kept apart, worked out with the author on 2026-10-19.

| Phase        | What is done                                                                                              | Done when                                        |
| ------------ | --------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| Theory       | Drafts in `docs/rfcs/`, and the model in `model/`                                                         | `mise run check --ready` passes, `docs/scope.md` |
| Simulation   | The model run through scenarios: a cold start, a component lost, a component upgraded, a contract changed | The same, since `check.res` runs them            |
| Comparison   | The design diffed against the code and designs that exist                                                 | Every component that exists has a fate           |
| Construction | Built from the ground up, in the order the bootstrap check gives                                          | The cold start is walked through once for real   |
| Hardening    | The error paths, the irreversible first                                                                   | Never                                            |

**One gate stands before construction, `--ready`**, worked out with the author on 2026-10-19: every
row blocking step 0 crossed off and every check holding, which is theory's completion -- every edge
reaching what the real world already provides, or marked by hand on day one or for later.
**Simulation runs inside it**: a cold start is D1, an upgrade D3, a contract changed D5, each run by
every check; a component lost is D4, a stage's later than `s0`, and is taken in with that stage.
**Comparison is a row of the checklist, and comes before a cutover, not before building**: the
platform is built from nothing on an account of its own and touches nothing that runs, so what each
service, Worker and store that exists becomes -- kept, replaced, moved or retired -- is settled
before the first of them moves onto it, a row of group D.

## A layer at a time

A layer is worked out whole before the next is begun, every area together. A need found at one layer
is written as an edge to a boundary of the next, a target beginning `?`, and is not followed down
until the layer it was found at is finished. The workspace's `spec/planning.md` states the same rule.

## Only what the author decided

A draft records what the author decided. A proposal they have not confirmed goes under Open, and so
does anything not discussed -- with no numbers in it.

## One decision at a time, the most urgent first

Agreed with the author on 2026-10-18. A question is brought to the author one at a time, in plain
words: what it is, why it must be decided now, the choices and what each costs, and a
recommendation. New questions are looked for only once the open one is decided.

The most urgent is chosen in this order: a contradiction in the core the model passes, since that
is a false proof; then what the most other questions wait on; then the rest. A detail -- a name, a
constant, a command -- waits until the structure it sits in is settled, however long the checklist
lists it. When the model passes what is a contradiction, the dimension or record that would catch
it is added to the model, so the check, not the conversation, proves it fixed.

## The model is the spec; a draft keeps the why

Agreed with the author on 2026-10-19. What a draft decides -- a table, a constant, a record's fields,
a contract -- is written once, in the model, and the draft points to the file that holds it; the
draft keeps its question, what was decided and why. A draft is dried this way when it is next
touched, not all at once. `docs/lessons/` stays as it is: it holds facts from outside, with their
sources, and none of the design.

## The tree grows by nesting, never by spreading

Agreed with the author on 2026-10-19. A directory holds at most 16 entries, the root excepted, decided
by the author on 2026-10-20, and lies at most 5 deep,
counted from a top-level directory or a package's root -- a directory with a `Cargo.toml`, a
`package.json` or a `rescript.json` -- its first subdirectory 1. What outgrows a directory is nested
in it as its abstraction rises, never laid beside the rest. Both numbers are for now: one reached
asks first whether it still fits the platform, and only then how the tree is cut below it.
`model/checks/layout/tree.res` holds both.

## A task is an entry, a script an order, a tool a program

Agreed with the author on 2026-10-19. **A mise task is five lines at most**, an entry and nothing
more; past that it is a script in `scripts/`, at the top, since it drives the model, the code and the
documents alike. **A script decides only order**: what runs, with which arguments, and where it
stops on a failure. **What computes is a tool**, a program in `code/tools/` with its tests: once a
script parses, converts or generates, that part is moved into a tool and the script calls it. Both
are ReScript, and TypeScript only where a library's surface is too wide to bind; Python never.

## The old system answers questions, never shapes the design

The code and designs that exist are read only to answer a question the model asks, and the answer is
written to `docs/lessons/` as a fact with its source. Their structure is never taken in: "how long can
an R2 object be cached" is a question to ask them, "how was the registry split into modules" is not.
Where possible, a reader separate from the design discussion reads them and brings back the answer
alone.

## The model grows by versions

The model covers what `docs/scope.md` lists -- its dimensions and its failure model -- and nothing more.
An edge case counts only when it falls in a listed class of failure; one that does not is written to
the out-of-model list and not designed for. A new version adds one class or one dimension at a time,
and the author decides each.
