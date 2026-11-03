---- MODULE storage ----
\* The storage's kind calls in order, as code/products/storage/src/operations.res takes them, while
\* writers and a deleter race one content and its names, any of them stopping for good between calls.
\* A write describes the content, writes it only where it has no size, then writes the name; a delete
\* deletes the name alone. The content may be lost once, as a store may lose it.
EXTENDS Naturals, Sequences, TLC

CONSTANTS
	Crashes,             \* A bound of the search, the actors that may stop for good in a run.
	NAME_BEFORE_CONTENT, \* A write takes write-name before write-content.
	DELETE_CONTENT       \* A delete removes the content with the name.

Actors == {"w1", "w2", "d1"}
Names == {"N1", "N2"}
Jobs == {"absent", "write N1", "write N2", "delete N1"}
Calls == {"describe-content", "write-content", "write-name", "delete-name"}
Stopped == {"done", "crashed", "absent"}

VARIABLES
	jobs,    \* What each actor does in this run, "absent" where the run has no such actor.
	content, \* Whether the content C is held.
	named,   \* What each name holds, "C" or "none".
	lost,    \* Whether the content was lost once.
	pc,      \* Each actor's next call, or why it makes none.
	sized,   \* Whether each writer's describe-content found C with a size.
	steps,   \* The steps taken, in order.
	crashes  \* The actors stopped for good so far.

vars == <<jobs, content, named, lost, pc, sized, steps, crashes>>

Writes(a) == jobs[a] \in {"write N1", "write N2"}
Target(a) == IF jobs[a] = "write N2" THEN "N2" ELSE "N1"
Held(n) == named[n] = "C"
Read(n) ==
	IF ~Held(n) THEN "not_found"
	ELSE IF content THEN "found"
	ELSE "unavailable"

Init ==
	/\ jobs \in {j \in [Actors -> Jobs] :
		/\ j["w1"] = "write N1"
		/\ j["w2"] \in {"absent", "write N1", "write N2"}
		/\ j["d1"] \in {"absent", "delete N1"}
		/\ (j["w2"] /= "absent" \/ j["d1"] /= "absent")}
	/\ content = FALSE
	/\ named = [n \in Names |-> "none"]
	/\ lost = FALSE
	/\ pc = [a \in Actors |->
		IF jobs[a] = "absent" THEN "absent"
		ELSE IF Writes(a) THEN "describe-content"
		ELSE "delete-name"]
	/\ sized = [a \in Actors |-> FALSE]
	/\ steps = <<>>
	/\ crashes = 0

Take(a, s) == steps' = Append(steps, a \o ":" \o s)
Goes(a, s) == pc' = [pc EXCEPT ![a] = s]

DescribeContent(a) ==
	/\ pc[a] = "describe-content"
	/\ sized' = [sized EXCEPT ![a] = content]
	/\ Goes(a, IF NAME_BEFORE_CONTENT \/ content THEN "write-name" ELSE "write-content")
	/\ Take(a, "describe-content")
	/\ UNCHANGED <<jobs, content, named, lost, crashes>>

WriteContent(a) ==
	/\ pc[a] = "write-content"
	/\ content' = TRUE
	/\ Goes(a, IF NAME_BEFORE_CONTENT THEN "done" ELSE "write-name")
	/\ Take(a, "write-content")
	/\ UNCHANGED <<jobs, named, lost, sized, crashes>>

WriteName(a) ==
	/\ pc[a] = "write-name"
	/\ named' = [named EXCEPT ![Target(a)] = "C"]
	/\ Goes(a, IF NAME_BEFORE_CONTENT /\ ~sized[a] THEN "write-content" ELSE "done")
	/\ Take(a, "write-name")
	/\ UNCHANGED <<jobs, content, lost, sized, crashes>>

DeleteName(a) ==
	/\ pc[a] = "delete-name"
	/\ named' = [named EXCEPT !["N1"] = "none"]
	/\ content' = IF DELETE_CONTENT THEN FALSE ELSE content
	/\ Goes(a, "done")
	/\ Take(a, "delete-name")
	/\ UNCHANGED <<jobs, lost, sized, crashes>>

\* Between two of its calls, after the first and before the last.
Crash(a) ==
	/\ pc[a] \in {"write-content", "write-name"}
	/\ crashes < Crashes
	/\ crashes' = crashes + 1
	/\ Goes(a, "crashed")
	/\ Take(a, "crash")
	/\ UNCHANGED <<jobs, content, named, lost, sized>>

\* The content lost once while the run goes on.
Lose ==
	/\ ~lost
	/\ content
	/\ \E a \in Actors : pc[a] \notin Stopped
	/\ content' = FALSE
	/\ lost' = TRUE
	/\ Take("env", "lose")
	/\ UNCHANGED <<jobs, named, pc, sized, crashes>>

Next ==
	\/ \E a \in Actors :
		\/ DescribeContent(a)
		\/ WriteContent(a)
		\/ WriteName(a)
		\/ DeleteName(a)
		\/ Crash(a)
	\/ Lose

Spec == Init /\ [][Next]_vars

TypeOK ==
	/\ jobs \in [Actors -> Jobs]
	/\ content \in BOOLEAN
	/\ named \in [Names -> {"C", "none"}]
	/\ lost \in BOOLEAN
	/\ pc \in [Actors -> Calls \cup Stopped]
	/\ sized \in [Actors -> BOOLEAN]
	/\ crashes \in 0..Crashes

\* A name held means C held, unless C was lost, after which a read of it answers unavailable.
NoNameWithoutContent ==
	\A n \in Names : Held(n) => Read(n) = "found" \/ (lost /\ Read(n) = "unavailable")

\* C is never removed while a name holds it, but by its loss.
ContentHeld ==
	[][(content /\ ~content' /\ \E n \in Names : Held(n)) => (~lost /\ lost')]_vars

\* A name once held always names C, held or deleted, never another content.
ObjectFixed ==
	[][\A n \in Names : Held(n) => named'[n] \in {"C", "none"}]_vars

\* Rows for the runner to gather into the fixture, each run once every actor has stopped.
Ended == \A a \in Actors : pc[a] \in Stopped
Word(b) == IF b THEN "1" ELSE "0"
Line(s) ==
	LET f[i \in 0..Len(s)] == IF i = 0 THEN "" ELSE f[i - 1] \o (IF i = 1 THEN "" ELSE ",") \o s[i]
	IN f[Len(s)]
Shown(j) ==
	CASE j = "write N1" -> "write_N1"
		[] j = "write N2" -> "write_N2"
		[] j = "delete N1" -> "delete_N1"
		[] OTHER -> "absent"
Present(a) == jobs[a] /= "absent"
Cast == LET order == SelectSeq(<<"w1", "w2", "d1">>, Present)
	IN [i \in 1..Len(order) |-> order[i] \o ":" \o Shown(jobs[order[i]])]
\* Only two-actor runs are printed, each race is two actors and three would swell the fixture.
Runs ==
	\/ ~Ended
	\/ Len(Cast) /= 2
	\/ PrintT("run actors=" \o Line(Cast) \o " steps=" \o Line(steps) \o " content=" \o Word(content)
		\o " names=" \o Line(SelectSeq(<<"N1", "N2">>, Held))
		\o " reads=N1:" \o Read("N1") \o ",N2:" \o Read("N2"))
====
