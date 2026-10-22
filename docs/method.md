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
until the layer it was found at is finished. The workspace's `docs/planning.md` states the same rule.

## Only what the author decided

An RFC records what the author decided, under `## Decision`, the workspace's RFC 2ut6h; a proposal
they have not confirmed, and anything not discussed, is a draft of its own, with no numbers in it.
Since 2026-10-22 a question decided in part is split: what is decided is `accepted`, or `landed`
once built, and what is open is a new draft beside it, RFC 1dj2c.

## A block's decisions in one round, the most urgent block first

Agreed with the author on 2026-10-18, and since 2026-10-20 a block's questions are brought
together, as the workspace's `docs/agent-protocol.md` has it, "The questions of one block are asked
together".

The most urgent block is chosen in this order: a contradiction in the core the model passes, since that
is a false proof; then what the most other questions wait on; then the rest. A detail -- a name, a
constant, a command -- waits until the structure it sits in is settled, however long the checklist
lists it. When the model passes what is a contradiction, the dimension or record that would catch
it is added to the model, so the check, not the conversation, proves it fixed.

## What only the platform half needs is written there

Decided by the author on 2026-10-20, RFC 8lkuv: a draft or a file here says what this half needs of
a role and stops; how the role is filled, and everything only the hosted platform asks, is written
in monoflake/cloud. What was published before stays as it was; from now on nothing more of it is
written here, and the silence check, `model/names/withheld.res`, refuses a name only the other
repository holds.

## The model is the spec; a draft keeps the why

Agreed with the author on 2026-10-19. What a draft decides -- a table, a constant, a record's fields,
a contract -- is written once, in the model, and the draft points to the file that holds it; the
draft keeps its question, what was decided and why. A draft is dried this way when it is next
touched, not all at once. `docs/lessons/` stays as it is: it holds facts from outside, with their
sources, and none of the design.

## The tree grows by nesting, never by spreading

Agreed with the author on 2026-10-19, and the workspace's rule since 2026-10-20: its
`docs/repos.md`, "A tree grows by nesting, never by spreading", gives the limits, and its check
holds this tree to them. Here a limit reached asks first whether the tree still fits the platform.

## A task is an entry, a script an order, a tool a program

Agreed with the author on 2026-10-19. A task is the workspace's entry, its lines limited there --
the workspace's `docs/toolchain.md`. Past that it is a script in `scripts/`, at the top, since it
drives the model, the code and the documents alike. **A script decides only order**: what runs, with which arguments, and where it
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
