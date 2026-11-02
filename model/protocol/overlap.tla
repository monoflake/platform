---- MODULE overlap ----
\* What the platform exports, a control and a driver within Reach interface steps can talk, in any order of moving.
\* The ranges are control's lowestRead in compatibility.res and the driver's in its listed.rs, RFC w0w82.
EXTENDS Naturals, Sequences, TLC

CONSTANTS
	Top,                      \* The highest interface version modeled.
	Reach,                    \* How many interface steps apart the export promises they overlap.
	EXACT_RANGE,              \* Control takes a driver at its own interface version alone.
	DRIVER_OWN_VERSION_ONLY,  \* A driver reports its own interface version as its whole range.
	TWO_BEHIND                \* The two are let drift one step past Reach.

VARIABLES control, driver

vars == <<control, driver>>

Max(a, b) == IF a > b THEN a ELSE b
Lowest(i) == Max(1, i - 1)
DriverLowest(i) == IF DRIVER_OWN_VERSION_ONLY THEN i ELSE Lowest(i)

\* Two ranges overlap where the lowest highest is no lower than either lowest.
Ranges(cl, ch, dl, dh) == cl <= dh /\ dl <= ch

Overlap(c, d) ==
	IF EXACT_RANGE
		THEN c = d
		ELSE Ranges(Lowest(c), c, DriverLowest(d), d)

Gap(a, b) == IF a > b THEN a - b ELSE b - a
Allowed(c, d) == Gap(c, d) <= (IF TWO_BEHIND THEN Reach + 1 ELSE Reach)

Init == control = 1 /\ driver = 1

\* Either side moves alone, up or down, so every order of moving is reached.
MoveControl ==
	\E c \in 1..Top :
		/\ Gap(c, control) = 1
		/\ Allowed(c, driver)
		/\ control' = c
		/\ UNCHANGED driver

MoveDriver ==
	\E d \in 1..Top :
		/\ Gap(d, driver) = 1
		/\ Allowed(control, d)
		/\ driver' = d
		/\ UNCHANGED control

Spec == Init /\ [][MoveControl \/ MoveDriver]_vars

\* In every state, in any order of moving them, the control can talk to the driver.
NoStuckDeploy == Overlap(control, driver)

\* One line per control and driver range, printed once, for control's tests to read through the runner.
Word(b) == IF b THEN "true" ELSE "false"
Row(c, l, h) ==
	"row {\"control\":" \o ToString(c) \o ",\"lowest\":" \o ToString(Lowest(c))
		\o ",\"driverLowest\":" \o ToString(l) \o ",\"driverHighest\":" \o ToString(h)
		\o ",\"overlaps\":" \o Word(Ranges(Lowest(c), c, l, h)) \o "}"
Table ==
	\/ control /= 1
	\/ driver /= 1
	\/ \A c, l, h \in 1..Top : l > h \/ PrintT(Row(c, l, h))
====
