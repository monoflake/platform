---- MODULE effect ----
\* One call to an `effect`, RFC 49qyg, through its holder, which issues the id, runs the function once,
\* tells the outcome and answers status(id) from the store. The holder is abstract, so this holds
\* wherever it runs. The function writes one batch or two, each atomic, behind a lock another writer
\* may hold for good; it or its reply may be lost; the id expires and the store refuses it after.
EXTENDS Naturals, Sequences, TLC

CONSTANTS
	Life,                   \* When the id expires, in ticks from its issue.
	Deadline,               \* How long the holder looks an outcome up before it is `unknown`.
	Wait,                   \* The longest wait for the lock before `unavailable`.
	ReplyBy,                \* The ticks the holder waits for a reply before it looks the outcome up.
	Faults,                 \* A bound of the search, the crashes and lost replies in a run.
	TIMEOUT_AS_UNAVAILABLE, \* A reply not come in time is told `unavailable`.
	APPLY_AFTER_EXPIRY,     \* The store commits a batch of an expired id.
	RETRY_ON_UNAVAILABLE,   \* The holder runs the function again on `unavailable`.
	SKIP_LOOKUP,            \* A reply not come in time is told `unknown` at once.
	SECOND_BATCH_SUCCESS,   \* A function stopped between its two batches is told a success.
	UNBOUNDED_LOCK_WAIT,    \* The function waits for the lock without bound.
	RECORD_SWEPT_AT_EXPIRY, \* The store forgets a call's batches once its id expires.
	ID_NEVER_EXPIRES        \* The store keeps an id open for good.

Outcomes == {"none", "success", "rejected", "unavailable", "unknown"}
Replies == {"none", "success", "rejected", "unavailable", "partial"}
Holding == {"start", "await", "lookup", "done"}
Running == {"idle", "waiting", "running", "done", "crashed"}

VARIABLES
	batches,  \* How many batches the call writes, one or two.
	holds,    \* Whether its condition holds, a conditional write failing `rejected` where not.
	locked,   \* Whether another writer holds the lock.
	clock,    \* Ticks since the id was issued.
	written,  \* The batches of this id the store committed.
	fpc,      \* The function's state.
	waited,   \* The tick its wait for the lock began.
	reply,    \* The function's reply in flight, "none" where none or lost.
	hpc,      \* The holder's state.
	from,     \* The tick the holder began looking up.
	outcome,  \* What the holder told the caller.
	runs,     \* How many times the holder ran the function.
	faults,   \* Crashes and lost replies so far.
	steps     \* The steps taken, in order.

vars == <<batches, holds, locked, clock, written, fpc, waited, reply, hpc, from, outcome, runs,
	faults, steps>>

Expired == ~ID_NEVER_EXPIRES /\ clock >= Life

\* Each batch carries the call's id and its sequence, committed in order in its own transaction, so
\* the store answers each sequence apart, and the last committed is the last step known.
BatchStatus(i) ==
	IF i <= written THEN "committed"
	ELSE IF Expired THEN "not_seen"
	ELSE "pending"

\* What the store holds for the id, which status(id) answers.
Status ==
	IF written = batches THEN "success"
	ELSE IF written > 0 THEN "partial"
	ELSE IF Expired THEN "not_seen"
	ELSE "pending"

Init ==
	/\ batches \in {1, 2}
	/\ holds \in BOOLEAN
	/\ locked \in BOOLEAN
	/\ clock = 0
	/\ written = 0
	/\ fpc = "idle"
	/\ waited = 0
	/\ reply = "none"
	/\ hpc = "start"
	/\ from = 0
	/\ outcome = "none"
	/\ runs = 0
	/\ faults = 0
	/\ steps = <<>>

Take(s) == steps' = Append(steps, s)

\* The holder issues the id and runs the function.
Begin ==
	/\ hpc = "start"
	/\ hpc' = "await"
	/\ fpc' = "waiting"
	/\ runs' = 1
	/\ Take("begin")
	/\ UNCHANGED <<batches, holds, locked, clock, written, waited, reply, from, outcome, faults>>

Acquire ==
	/\ fpc = "waiting"
	/\ ~locked
	/\ fpc' = "running"
	/\ Take("acquire")
	/\ UNCHANGED <<batches, holds, locked, clock, written, waited, reply, hpc, from, outcome, runs,
		faults>>

\* Past the wait the function fails `unavailable`, having written nothing.
WaitOut ==
	/\ fpc = "waiting"
	/\ ~UNBOUNDED_LOCK_WAIT
	/\ clock >= waited + Wait
	/\ fpc' = "done"
	/\ reply' = "unavailable"
	/\ Take("wait-out")
	/\ UNCHANGED <<batches, holds, locked, clock, written, waited, hpc, from, outcome, runs, faults>>

\* The other writer lets the lock go, or never does.
Release ==
	/\ locked
	/\ locked' = FALSE
	/\ Take("release")
	/\ UNCHANGED <<batches, holds, clock, written, fpc, waited, reply, hpc, from, outcome, runs,
		faults>>

\* One batch: refused at once where the condition fails, refused where the id expired, else committed.
Batch ==
	/\ fpc = "running"
	/\ IF written = 0 /\ ~holds THEN
			/\ fpc' = "done"
			/\ reply' = "rejected"
			/\ UNCHANGED written
			/\ Take("rejected")
		ELSE IF Expired /\ ~APPLY_AFTER_EXPIRY THEN
			/\ fpc' = "done"
			/\ reply' = IF written = 0 THEN "unavailable" ELSE "partial"
			/\ UNCHANGED written
			/\ Take("expired")
		ELSE
			/\ written' = written + 1
			/\ fpc' = IF written + 1 = batches THEN "done" ELSE "running"
			/\ reply' = IF written + 1 = batches THEN "success" ELSE reply
			/\ Take("commit")
	/\ UNCHANGED <<batches, holds, locked, clock, waited, hpc, from, outcome, runs, faults>>

Crash ==
	/\ fpc \in {"waiting", "running"}
	/\ faults < Faults
	/\ faults' = faults + 1
	/\ fpc' = "crashed"
	/\ Take("crash")
	/\ UNCHANGED <<batches, holds, locked, clock, written, waited, reply, hpc, from, outcome, runs>>

LoseReply ==
	/\ reply /= "none"
	/\ faults < Faults
	/\ faults' = faults + 1
	/\ reply' = "none"
	/\ Take("lose-reply")
	/\ UNCHANGED <<batches, holds, locked, clock, written, fpc, waited, hpc, from, outcome, runs>>

\* A reply taken: told as it says, a function stopped between two batches looked up.
Receive ==
	/\ hpc = "await"
	/\ reply /= "none"
	/\ reply' = "none"
	/\ IF reply = "unavailable" /\ RETRY_ON_UNAVAILABLE /\ runs < 2 THEN
			/\ runs' = runs + 1
			/\ fpc' = "waiting"
			/\ waited' = clock
			/\ UNCHANGED <<hpc, from, outcome>>
		ELSE IF reply = "partial" /\ ~SECOND_BATCH_SUCCESS THEN
			/\ hpc' = "lookup"
			/\ from' = clock
			/\ UNCHANGED <<runs, fpc, waited, outcome>>
		ELSE
			/\ hpc' = "done"
			/\ outcome' = IF reply = "partial" THEN "success" ELSE reply
			/\ UNCHANGED <<runs, fpc, waited, from>>
	/\ Take("receive-" \o reply)
	/\ UNCHANGED <<batches, holds, locked, clock, written, faults>>

\* No reply in time: the outcome is looked up.
TimeOut ==
	/\ hpc = "await"
	/\ reply = "none"
	/\ clock >= ReplyBy
	/\ IF TIMEOUT_AS_UNAVAILABLE \/ SKIP_LOOKUP THEN
			/\ hpc' = "done"
			/\ outcome' = IF SKIP_LOOKUP THEN "unknown" ELSE "unavailable"
			/\ UNCHANGED from
		ELSE
			/\ hpc' = "lookup"
			/\ from' = clock
			/\ UNCHANGED outcome
	/\ Take("time-out")
	/\ UNCHANGED <<batches, holds, locked, clock, written, fpc, waited, reply, runs, faults>>

\* Asking after the id: a definite answer told, else `unknown` once the deadline passed.
Lookup ==
	/\ hpc = "lookup"
	/\ \/ (Status = "success" /\ outcome' = "success")
		\/ (Status = "not_seen" /\ outcome' = "unavailable")
		\/ (Status \in {"pending", "partial"} /\ clock >= from + Deadline /\ outcome' = "unknown")
	/\ hpc' = "done"
	/\ Take("lookup-" \o Status)
	/\ UNCHANGED <<batches, holds, locked, clock, written, fpc, waited, reply, from, runs, faults>>

\* Time runs to the id's expiry, and past it while a lookup waits out its deadline.
Tick ==
	/\ hpc /= "start"
	/\ clock < Life \/ (hpc = "lookup" /\ clock < from + Deadline)
	/\ clock' = clock + 1
	/\ Take("tick")
	/\ UNCHANGED <<batches, holds, locked, written, fpc, waited, reply, hpc, from, outcome, runs,
		faults>>

Holder == Begin \/ Receive \/ TimeOut \/ Lookup
Function == Acquire \/ WaitOut \/ Batch

\* The defect a sweep makes, the batches forgotten while the id may still be asked after.
Sweep ==
	/\ RECORD_SWEPT_AT_EXPIRY
	/\ Expired
	/\ written > 0
	/\ written' = 0
	/\ Take("sweep")
	/\ UNCHANGED <<batches, holds, locked, clock, fpc, waited, reply, hpc, from, outcome, runs,
		faults>>

Next == Holder \/ Function \/ Release \/ Crash \/ LoseReply \/ Tick \/ Sweep

\* The lock may never be let go, and a crash or a lost reply may never come.
Fair == WF_vars(Holder) /\ WF_vars(Function) /\ WF_vars(Tick)

Spec == Init /\ [][Next]_vars /\ Fair

TypeOK ==
	/\ batches \in {1, 2}
	/\ holds \in BOOLEAN
	/\ locked \in BOOLEAN
	/\ clock \in 0..(Life + Deadline)
	/\ written \in 0..batches
	/\ fpc \in Running
	/\ reply \in Replies
	/\ hpc \in Holding
	/\ outcome \in Outcomes
	/\ runs \in 0..2
	/\ faults \in 0..Faults

\* Success only where every batch committed; a definite failure only where none did, nor ever will.
Truthful ==
	/\ outcome = "success" => written = batches
	/\ outcome \in {"rejected", "unavailable"} => written = 0

\* No batch of an expired id commits, so "not seen" after expiry is certain.
NeverAfterExpiry == [][written' > written => ~Expired]_vars

\* `unknown` only once the lookup's deadline passed with no definite answer.
UnknownOnlyAfterLookup == outcome = "unknown" => hpc = "done" /\ clock >= from + Deadline /\ from > 0

\* status(id), once it answers a batch committed or not seen, keeps that answer for it.
StatusAgrees ==
	[][\A i \in 1..batches :
		(BatchStatus(i) \in {"committed", "not_seen"}) => (BatchStatus(i)' = BatchStatus(i))]_vars

\* The holder runs a call at most once.
NeverRetried == runs <= 1

\* A call whose first batch committed and second did not is never told a success or a failure.
TwoBatchesUnknown == (batches = 2 /\ written = 1 /\ outcome /= "none") => outcome = "unknown"

\* Every call ends, its function stopped and its outcome told.
Ends == <>(outcome /= "none" /\ fpc \in {"done", "crashed"})

\* An `unknown`'s status(id) answers once the store can.
Settles == outcome = "unknown" ~> Status \in {"success", "not_seen", "partial"}

\* Rows for a replay, each run once it ended: its case, its steps and its end, keys fixed.
Ended == hpc = "done" /\ fpc \in {"done", "crashed", "idle"}
Word(b) == IF b THEN "1" ELSE "0"
Line(s) ==
	LET f[i \in 0..Len(s)] == IF i = 0 THEN "" ELSE f[i - 1] \o (IF i = 1 THEN "" ELSE ",") \o s[i]
	IN f[Len(s)]
Runs ==
	\/ ~Ended
	\/ PrintT("run batches=" \o ToString(batches) \o " holds=" \o Word(holds)
		\o " locked=" \o Word(locked) \o " steps=" \o Line(steps)
		\o " written=" \o ToString(written) \o " outcome=" \o outcome \o " status=" \o Status
		\o " batches=" \o Line([i \in 1..batches |-> ToString(i) \o ":" \o BatchStatus(i)]))
====
