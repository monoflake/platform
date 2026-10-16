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

**What a problem is.** A rule of a dimension broken, within the failure model of the version in
force. What lies outside the failure model is out of the model, written down and not designed for;
what a `soft` edge costs -- slower, staler, more garbage -- is a cost, not a problem.

**The system has three boundaries.**

| Boundary         | What it is                                                                   | How the model treats it                                                           |
| ---------------- | ---------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| above            | layer 0's three interfaces                                                   | an app is their user; an app's own mistake is not the platform's problem          |
| below, ground    | a vendor's written guarantee, a proven algorithm, a physical fact            | trusted and never designed; the failures it states are taken into a failure model |
| beside, operator | a person, holding the root private key and running day one's manual commands | ideal, above                                                                      |

**The model holds five kinds of thing**: a part, which runs and has a layer; a library, code with no
layer that uses only libraries; the ground; the operator; and a boundary, written `?name`, something
a part needs that no part is yet.

**Each edge carries three attributes**: when it is needed, `start`, `serve`, `deploy` or
`background`; what its loss does, `hard`, wrong or stopped, or `soft`, slower or staler and never
wrong; and its contract, who defines the format crossing it.

**A format carried unread is exempt from the contract.** A tablet holding the function product's
rows runs SQL, whose rules are its own, and reads nothing of what the rows mean: a renamed column
changes nothing for it. The issuer reading the same rows to decide what to sign must know each
column, and a renamed one breaks it. A lower part may carry an upper part's format, never read it;
an upper part may write into a format a lower one defines.

**Five dimensions**, each a question, the edges it reads, and what violates it:

| Dimension    | Question                                                                           | Reads                             | Violated by                                                                                    |
| ------------ | ---------------------------------------------------------------------------------- | --------------------------------- | ---------------------------------------------------------------------------------------------- |
| D1 bootstrap | From the ground and the operator alone, can every part come up the first time?     | `start`, `deploy`                 | a cycle; an edge to a boundary; a `hard` edge pointing up                                      |
| D2 restart   | After everything stops, can every part come back from what it kept?                | `start`, and what each part keeps | a part whose restart needs what lives only in another's memory; a cycle                        |
| D3 upgrade   | While the rest runs, can one part be replaced by a new version?                    | `deploy`, and the contracts       | replacing a part needs itself; two ends of an edge with no version in common; no `deploy` edge |
| D4 recovery  | With one part lost, does the data plane keep serving, and does the part come back? | `hard` `serve`                    | a part lost stops the data plane; its way back needs what has stopped                          |
| D5 contract  | Is every format a part reads defined at its own layer or below?                    | the contracts                     | a lower part reading an upper part's format                                                    |

## v0

The correct path alone: no failure is modeled.

**Rules beneath every dimension.** A `hard` edge points to its own layer or below; a `soft` edge
may point up. A library uses only libraries.

**Dimensions run.** D1 bootstrap, D2 restart of a planned stop, D3 upgrade and D5 contract, by
`node model/check.ts`. D4 recovery models a failure and is v1's, run with `--v1`.

**Out of the model in v0:** every failure, including one part crashing and one store lost, which
are the first a later version takes in; performance and cost; an operator's mistake.

Open, for v0:

- Sorting each boundary the model has found into: decided now, since a mistake is written into data
  and cannot be undone; done by hand on day one, with its command; or left for later, with what
  brings it back.
