---- MODULE footing ----
\* The footing's interface, read, write and lease, as RFC n8jq5 and 8yl4b decide them, RFC w0w82.
\* A write names the lease its writer holds, checked by the footing's clock inside its one D1 batch.
\* D1's batch is ground and lands in one step; time is relative, each lease counting its ticks left.
EXTENDS Naturals, FiniteSets, TLC

CONSTANTS
	Instances,            \* The instances of one component that take the lease, each by its key's kid.
	Rows,                 \* The rows a change writes and a reader pages through, one row a page.
	Seconds,              \* The ticks of the footing's clock a take or a renew grants.
	Top,                  \* The highest generation modeled, so the writes are bounded.
	TAKE_BEFORE_PASSED,   \* A take is answered while another's lease has not passed.
	CHECK_BEFORE_BATCH,   \* A write's lease is checked in a step of its own before its batch.
	STATEMENT_AT_A_TIME,  \* A batch runs as statements, a failed condition keeping the earlier ones.
	PAGES_UNPINNED,       \* A later page reads the newest rows, not the generation its cursor began at.
	NO_EXPIRY             \* A lease is held until released, its until never read.

None == "none"
Pages == 1..Rows
Gens == 0..Top
Request == [rows : SUBSET Pages, read : Gens, held : {"unchecked", "yes", "no"}]
NoRequest == [rows |-> {}, read |-> 0, held |-> "unchecked"]
Entry == [asked : SUBSET Pages, wrote : SUBSET Pages, held : BOOLEAN]

VARIABLES
	lease,    \* The lease's row, its holder and the ticks left before its until.
	grant,    \* The ticks left of what each instance was last answered, a ghost of what it holds.
	stopped,  \* The instances that stopped, their requests already sent still landing.
	gen,      \* The footing's one generation counter, advanced in the batch of every write.
	hist,     \* The rows as each generation left them, each row named by the generation that wrote it.
	log,      \* What each generation's write asked and wrote, and whether its writer held the lease.
	pending,  \* Each instance's write sent and not yet answered.
	reader    \* A reader paging through the rows, the generation its cursor began at.

lessee == <<lease, grant, stopped>>
store == <<gen, hist, log>>
vars == <<lease, grant, stopped, gen, hist, log, pending, reader>>

Fresh == [page |-> 0, at |-> 0, seen |-> [p \in Pages |-> 0]]

Init ==
	/\ lease = [holder |-> None, left |-> 0]
	/\ grant = [i \in Instances |-> 0]
	/\ stopped = {}
	/\ gen = 0
	/\ hist = [g \in Gens |-> [p \in Pages |-> 0]]
	/\ log = [g \in Gens |-> [asked |-> {}, wrote |-> {}, held |-> TRUE]]
	/\ pending = [i \in Instances |-> NoRequest]
	/\ reader = Fresh

Dec(n) == IF n > 0 THEN n - 1 ELSE 0

\* What the footing judges a lease by, and what holds by its clock whatever the footing reads.
Valid(i) == lease.holder = i /\ (NO_EXPIRY \/ lease.left > 0)
Holds(i) == lease.holder = i /\ lease.left > 0

\* Once a lease lapses anyone may take it; while it is held another's take answers held.
Take(i) ==
	/\ i \notin stopped
	/\ \/ lease.holder = None
	   \/ ~NO_EXPIRY /\ lease.left = 0
	   \/ TAKE_BEFORE_PASSED /\ lease.holder /= i
	/\ lease' = [holder |-> i, left |-> Seconds]
	/\ grant' = [grant EXCEPT ![i] = Seconds]
	/\ UNCHANGED <<stopped, store, pending, reader>>

\* Only the holder renews, before its lease passed; after, it takes the lease again.
Renew(i) ==
	/\ i \notin stopped
	/\ Valid(i)
	/\ lease' = [lease EXCEPT !.left = Seconds]
	/\ grant' = [grant EXCEPT ![i] = Seconds]
	/\ UNCHANGED <<stopped, store, pending, reader>>

Release(i) ==
	/\ i \notin stopped
	/\ lease.holder = i
	/\ lease' = [holder |-> None, left |-> 0]
	/\ grant' = [grant EXCEPT ![i] = 0]
	/\ UNCHANGED <<stopped, store, pending, reader>>

\* One instance stays running, so a takeover has someone to make it.
Stop(i) ==
	/\ i \notin stopped
	/\ Cardinality(stopped) + 1 < Cardinality(Instances)
	/\ stopped' = stopped \cup {i}
	/\ UNCHANGED <<lease, grant, store, pending, reader>>

\* The footing's clock moves for every lease and every answer alike.
Tick ==
	/\ lease.left > 0 \/ \E i \in Instances : grant[i] > 0
	/\ lease' = [lease EXCEPT !.left = Dec(@)]
	/\ grant' = [i \in Instances |-> Dec(grant[i])]
	/\ UNCHANGED <<stopped, store, pending, reader>>

\* A holder reads the rows and sends a change on them, each row conditional at the generation read.
Send(i) ==
	/\ i \notin stopped
	/\ grant[i] > 0
	/\ pending[i].rows = {}
	/\ gen < Top
	/\ \E rows \in SUBSET Pages \ {{}} :
		pending' = [pending EXCEPT ![i] = [rows |-> rows, read |-> gen, held |-> "unchecked"]]
	/\ UNCHANGED <<lessee, store, reader>>

Check(i) ==
	/\ CHECK_BEFORE_BATCH
	/\ pending[i].rows /= {}
	/\ pending[i].held = "unchecked"
	/\ pending' = [pending EXCEPT ![i].held = IF Valid(i) THEN "yes" ELSE "no"]
	/\ UNCHANGED <<lessee, store, reader>>

\* The batch, the lease's statement and every row's, landing whole or answered stale or held.
Apply(i) ==
	LET p == pending[i]
		Met(k) == hist[gen][k] = hist[p.read][k]
		leased == IF CHECK_BEFORE_BATCH THEN p.held = "yes" ELSE Valid(i)
		landed ==
			IF STATEMENT_AT_A_TIME
				THEN {k \in p.rows : \A m \in p.rows : m <= k => Met(m)}
				ELSE IF \A k \in p.rows : Met(k) THEN p.rows ELSE {}
		wrote == IF leased /\ gen < Top THEN landed ELSE {}
	IN
	/\ p.rows /= {}
	/\ CHECK_BEFORE_BATCH => p.held /= "unchecked"
	/\ pending' = [pending EXCEPT ![i] = NoRequest]
	/\ IF wrote = {}
		THEN UNCHANGED store
		ELSE
			/\ gen' = gen + 1
			/\ hist' = [hist EXCEPT ![gen + 1] =
				[k \in Pages |-> IF k \in wrote THEN gen + 1 ELSE hist[gen][k]]]
			/\ log' = [log EXCEPT ![gen + 1] = [asked |-> p.rows, wrote |-> wrote, held |-> Holds(i)]]
	/\ UNCHANGED <<lessee, reader>>

\* A page a call, the cursor naming the generation the first page was read at.
ReadPage ==
	/\ reader.page < Rows
	/\ LET p == reader.page + 1
		at == IF p = 1 THEN gen ELSE reader.at
		from == IF PAGES_UNPINNED THEN gen ELSE at
	   IN reader' = [page |-> p, at |-> at, seen |-> [reader.seen EXCEPT ![p] = hist[from][p]]]
	/\ UNCHANGED <<lessee, store, pending>>

Again ==
	/\ reader.page = Rows
	/\ reader' = Fresh
	/\ UNCHANGED <<lessee, store, pending>>

Next ==
	\/ Tick \/ ReadPage \/ Again
	\/ \E i \in Instances :
		Take(i) \/ Renew(i) \/ Release(i) \/ Stop(i) \/ Send(i) \/ Check(i) \/ Apply(i)

\* Time passes, and a running instance that wants a lapsed lease asks for it.
Fairness == WF_vars(Tick) /\ \A i \in Instances : WF_vars(Take(i))

Spec == Init /\ [][Next]_vars /\ Fairness

TypeOK ==
	/\ lease \in [holder : Instances \cup {None}, left : 0..Seconds]
	/\ grant \in [Instances -> 0..Seconds]
	/\ stopped \subseteq Instances
	/\ gen \in Gens
	/\ hist \in [Gens -> [Pages -> Gens]]
	/\ log \in [Gens -> Entry]
	/\ pending \in [Instances -> Request]
	/\ reader \in [page : 0..Rows, at : Gens, seen : [Pages -> Gens]]

\* Two instances never both hold the lease by the footing's clock.
OneHolder == \A i, j \in Instances : i /= j => ~(grant[i] > 0 /\ grant[j] > 0)

\* Every write that landed landed while its writer held the lease.
PassedLeaseRefused == \A g \in 1..gen : log[g].held

\* Every write that landed wrote each row it asked for.
AllOrNone == \A g \in 1..gen : log[g].wrote = log[g].asked

\* A reader's pages together are the rows as one generation left them.
WholeBatches == reader.page = Rows => \E g \in 0..gen : reader.seen = hist[g]

\* A lease whose holder stopped is taken over once it passes.
TakenOver == \A i \in Instances : (i \in stopped /\ lease.holder = i) ~> lease.holder /= i
====
