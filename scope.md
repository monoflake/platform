# Scope

What the model covers in its current stage. An edge case outside it goes to the out-of-model list
and is not designed for until a later stage takes it in. See `spec/process.md`.

**Building begins when `node model/check.ts --ready` passes**: every row of `model/checklist.ts`
that blocks step 0 is crossed off by naming where it was decided, and every check holds. **The
checklist grows by itself**: every open question a draft lists, and every open mark in the model,
names its row in brackets, `[B12]`; one that names none is unfiled and blocks, so a new dimension
or structure brings its questions in. A later step is gated the same way, `--ready=N`.

**Two numberings, never one.** A stage, `s0`, `s1`, is how far the paper model reaches; a version,
`v0`, `v1`, is a release of the Platform, RFC 94y0d. What each stage takes in beyond `s0` is to be
discussed again, since the internal and external platforms changed what it must cover.

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

| Boundary         | What it is                                                                              | How the model treats it                                                           |
| ---------------- | --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| above            | layer 0's three interfaces                                                              | an app is their user; an app's own mistake is not the platform's problem          |
| below, ground    | a vendor's written guarantee, a published standard, a proven algorithm, a physical fact | trusted and never designed; the failures it states are taken into a failure model |
| beside, operator | a person, holding the root private key and running day one's manual commands            | ideal, above                                                                      |

**The footing is ground: trusted and never designed.** A footing is what an owner stands on from
beneath it: one compute, which keeps nothing; one storage; and one database, each meeting one kind
of its class at least, RFC vr5lw. A control stands on it and nothing else does: the platform's
footing, from the layer beneath, under the platform's control; and each
organization's, which the platform gives it, under that organization's own control. What is kept
is backed up, the database and the storage, and only the database is held to the contract below.
The platform stands on one database, RFC v7v3w,
which the model takes to be up and to keep what it confirmed; whether it is made redundant is
beneath its contract and its owner's. **Its contract is frozen and carries no version**: SQLite's
dialect; atomic batches, a fixed list of statements that all hold or none, never a transaction that
reads and then decides; at most 10 GB, or less where its vendor's plan holds less, revised when the
vendor is; and reached from every compute. Changing the vendor beneath a
footing, or its contract, is a planned stop, by hand: its owner stops, the footing is copied,
checked and switched to, and the old one is removed only after, which the 10 GB bound keeps to
minutes. A footing down stops its owner, which is reversible; a footing losing data is guarded
against by its vendor's written durability and by a backup held offline. The platform's footing
stopping stops the control plane alone, and every organization runs on through it on its
certificate.

**What a footing keeps is bounded; what it is asked may grow.** It never grows with the content its
owner holds, nor with time: a journal is kept in the stores, a log bounded by its archiving. Its
reads and writes may grow with use, and how far each step of the bootstrap path asks of its
vendor's plan is counted, `model/footing.ts`.

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

**Six dimensions**, each a question, the edges it reads, and what violates it:

| Dimension    | Question                                                                           | Reads                             | Violated by                                                                                    |
| ------------ | ---------------------------------------------------------------------------------- | --------------------------------- | ---------------------------------------------------------------------------------------------- |
| D0 serve     | On the correct path, does every operation the products promise reach the ground?   | `serve`                           | a `serve` edge to a boundary with no contract                                                  |
| D1 bootstrap | From the ground and the operator alone, can every part come up the first time?     | `start`, `deploy`                 | a cycle; an edge to a boundary with no contract; a `hard` edge pointing up                     |
| D2 restart   | After everything stops, can every part come back from what it kept?                | `start`, and what each part keeps | a part whose restart needs what lives only in another's memory; a cycle                        |
| D3 upgrade   | While the rest runs, can one part be replaced by a new version?                    | `deploy`, and the contracts       | replacing a part needs itself; two ends of an edge with no version in common; no `deploy` edge |
| D4 recovery  | With one part lost, does the data plane keep serving, and does the part come back? | `hard` `serve`                    | a part lost stops the data plane; its way back needs what has stopped                          |
| D5 contract  | Is every format a part reads defined at its own layer or below?                    | the contracts                     | a lower part reading an upper part's format                                                    |

**A lower part may deliver to an upper one: the envelope points down, the letter may mean
something only above.** Delivering is not depending. What a delivery travels by -- a route table,
an address's prefix -- is an envelope, and its format is defined below, so the structure depends only
downward. What it carries is a letter, carried unread, which may mean something only at a layer
above, as IP reads its own header and carries a TCP segment as bytes. A part that delivers upward
keeps running when what it delivers to is down, and answers that it is unavailable; the table it
delivers by is written by the upper part, at deployment, in the lower part's format.

**A boundary is a contract, and a layer is checked against it.** A boundary `?name` states what it
must guarantee: what it provides, and what the dimensions require of it through the parts that need
it -- one an executor needs to start must itself start before the executor and without it. A layer is
then checked as it stands: if every boundary beneath it keeps its contract, does the layer satisfy
every dimension? An edge to a boundary with a contract is an assumption, passed and listed; one to a
boundary without is a violation. Nothing beneath a layer need exist for it to be checked.

**A layer is closed when** its own violations are fixed and every boundary it points down to has its
contract written. Only then is the next layer begun, whose work is to keep those contracts and write
its own. At the ground the last contracts are kept by what the real world provides, and the system
holds by composition, without a complete model at any point between.

## s0

The correct path alone: no failure is modeled.

**Rules beneath every dimension.** A `hard` edge points to its own layer or below; a `soft` edge
may point up. A library uses only libraries. Nothing at layer 0 or below has an edge, `hard` or
`soft`, to what the platform runs as an owner, so the graph stays clean while the platform runs on
itself, RFC vuanj. The data plane writes no configuration: whatever an organization opens -- a dataset, a
database, an app -- is configuration, the platform's half, written on the control plane alone,
whoever asks, RFC v7v3w; `RECORDS` in `model/graph.ts` lists each kind of record.

**Dimensions run.** D0 serve, D1 bootstrap, D2 restart of a planned stop, D3 upgrade and D5
contract, by `node model/check.ts`, and then the bootstrap path, `model/bootstrap.ts`: every step of
RFC 94y0d holds, each deployment reaches it by a move it may take, and what its ground gives,
`model/resources.ts`, makes a footing of one kind of each class and extensions that give what the
products need, RFC vr5lw; and the footing,
`model/footing.ts`: what each keeps is bounded, and each step fits the rows a day its plan allows. D4 recovery models a failure
and is s1's, run with `--s1`.

**Out of the model in s0:** every failure, including one part crashing and one store lost, which
are the first a later stage takes in; a replacement that fails, and rolling it back; replacing
more than one part at once; performance, and cost past a footing's rows; an operator's mistake.

**Each contract is sorted** into one of three: decided now, since a mistake is written into data
and cannot be undone; kept by hand on day one, with its command; or left for later, with what brings
it back. The boundaries' sorting is in `model/graph.ts`, and `node model/check.ts` reports any not
yet sorted.

| Contract        | Sorted             |
| --------------- | ------------------ |
| `?deployer`     | by hand on day one |
| `?roster`       | by hand on day one |
| `?source`       | by hand on day one |
| `?entry`        | by hand on day one |
| `?runner`       | by hand on day one |
| `?intermediate` | by hand on day one |
| `?egress`       | later              |
| `?clock`        | later              |

**Decided now**, before the first byte is written, since each is written into every piece of data
and a mistake in it is never undone: how a scope's salt is derived, the hash content is named by,
how content is cut, and the format a container is sealed in -- BLAKE3, FastCDC, and AES-256-GCM in
fixed segments, each decided in RFC b8f35.
