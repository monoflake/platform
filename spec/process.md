# Process

How the design is worked out, agreed with the author on 2026-10-15. The old platform was built a
step at a time without a design that held together in theory, and could not carry a stable app; this
one is made to hold together on paper first.

## Five stages, in order

| Stage        | What is done                                                                                    | Done when                                                  |
| ------------ | ----------------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| Theory       | Drafts in `rfcs/`, and the model in `model/`                                                    | The completion rule below holds                            |
| Simulation   | The model run through scenarios: a cold start, a part lost, a part upgraded, a contract changed | Every scenario has a result; a failure goes back to theory |
| Comparison   | The design diffed against the code and designs that exist                                       | Every existing component has a fate                        |
| Construction | Built from the ground up, in the order the bootstrap check gives                                | The cold start is walked through once for real             |
| Hardening    | The error paths, the irreversible first                                                         | Never                                                      |

**The completion rule of theory**: every edge in the model either reaches something the real world
already provides -- a vendor's guarantee, a published standard, a proven algorithm, a physical fact
-- or is marked to be done by hand on day one or left for later; and every check passes, or each
violation is written down with the manual path that recovers from it.

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

## The old system answers questions, never shapes the design

The code and designs that exist are read only to answer a question the model asks, and the answer is
written to `lessons.md` as a fact with its source. Their structure is never taken in: "how long can
an R2 object be cached" is a question to ask them, "how was the registry split into modules" is not.
Where possible, a reader separate from the design discussion reads them and brings back the answer
alone.

## The model grows by versions

The model covers what `scope.md` lists -- its dimensions and its failure model -- and nothing more.
An edge case counts only when it falls in a listed class of failure; one that does not is written to
the out-of-model list and not designed for. A new version adds one class or one dimension at a time,
and the author decides each.
