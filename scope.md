# Scope

What the model covers in its current version. An edge case outside it goes to the out-of-model list
and is not designed for until a later version takes it in. See `spec/process.md`.

## Decided

**The correct path first.** The model first proves on paper that the platform starts and runs when
nothing goes wrong; only then does it ask which error paths carry a cost that cannot be undone. A
failure is not modeled before the correct path holds.

**A problem is reversible or irreversible, nothing finer.** Irreversible is data lost, or a wrong
format written into data; reversible is an outage some path recovers from. The distinction exists so
that, once the platform runs, the irreversible cost never occurs; finer classes wait until it runs.

**The operator is ideal.** A person makes mistakes no model foresees, and simulating them costs more
than anything else here, so the model assumes the operator runs each command as written. An
operator's mistake is out of the model.

**The data plane keeps serving while the control plane is lost.**

| Plane   | What it does                                                        | While the control plane is lost |
| ------- | ------------------------------------------------------------------- | ------------------------------- |
| data    | reads and writes data that exists, calls functions already deployed | keeps serving                   |
| control | creates or changes configuration, deploys                           | may be unreachable              |

What is already running needs nothing from the control plane to go on running; when the control
plane returns, it takes over again.

## v0

The correct path alone: no failure is modeled.

**Dimensions.** Each edge carries:

- when it is needed: `start`, `serve`, `deploy` or `background`;
- what its loss does: `hard`, wrong or stopped, or `soft`, slower, staler or more garbage and never
  wrong.

A `hard` edge points to its own layer or below; a `soft` edge may point up. A library uses only
libraries.

**Checks.** Bootstrap, the order the `start` edges allow from the ground up. Upgrade, what replaces
each part.

**Out of the model in v0:** every failure, including one part crashing and one store lost, which
are the first a later version takes in; performance and cost; an operator's mistake.

Open, for v0:

- The definitions proposed on 2026-10-15, not yet confirmed: what a problem is; the system's three
  boundaries -- layer 0's interfaces above, the ground below, the operator beside; the five kinds of
  thing in the model -- part, library, ground, operator, boundary; a third attribute on each edge,
  the contract, who defines the format crossing it and whether the receiver reads it or carries it
  unread; and the five dimensions -- bootstrap, restart, upgrade, recovery, contract -- each with its
  question, the edges it reads and what violates it.
- Whether a part that carries a format unread, as a tablet holds another part's rows, is exempt from
  the contract dimension, which a part that reads it, as the issuer reads the function product's
  rows, is not.
- Sorting each boundary the model has found into: decided now, since a mistake is written into data
  and cannot be undone; done by hand on day one, with its command; or left for later, with what
  brings it back.
