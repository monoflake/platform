---
name: 'The As-Built Graph'
title: "Each block declares the names it provides, and the as-built graph made of them is held to the design's rules, its violations the scaffolds"
status: accepted
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

The model's graph is the design: its components, roles and boundaries, and the edges between them.
What code fills which of those names is written nowhere a check reads: a block is matched to the one
component its directory and package are named for, so a block that stands in for several names, or
for a name in part, is described as the one it is named for, and a check that passes says nothing
of what runs. How is what is built related to what is designed, so the model describes what runs?

## Decision

Decided by the author on 2026-10-24.

**A block and a component are apart.** A block declares `provides`, the names of the components,
roles and boundaries it provides. One block may provide more than one name, and one name may be
provided by more than one block. A block declares only which names it provides, never how far it
provides them. **A block is still named for one main name**, its directory and its package named
from it as now, and `provides` lists the names it provides beside that one.

**The as-built graph is derived.** It is, for every block, the design graph's edges of each name the
block provides, together with the extra edges the block declares. A block declares an extra edge
only where the design graph has none. **A block may also declare, for a design edge of a name it
provides, the contract that edge carries as built**, amended by the author on 2026-10-24: in the
as-built graph that edge carries the declared contract in place of the design's. Only the contract
changes; no design edge is removed. A contract so declared that is not declared in the model is
reported by Crossing, a scaffold. An edge's type gains a mark that its target is on the platform
beneath, RFC 94y0d.

**An edge is in the as-built graph only where a block provides its source**, or where a block
declares it as an extra edge, amended by the author on 2026-10-24. A name no block provides brings
none of its edges, since a component with no code has no edge that runs; an edge to it stands where
its source is provided. **An edge to a boundary `?x`, pointed at a block that provides `?x`, carries
`?x` as its contract**, and that block answers `?x` by its `provides`, amended by the author on
2026-10-24: the design writes no contract on an edge to a boundary, whose contract is its prose, and
without it Crossing would report every block that rightly provides a boundary.

**One set of rules runs twice.**

- The design graph is checked as it is now, and a violation there is refused.
- The as-built graph is checked by the same rules, and a violation there is reported, not refused.
  The list of violations on the as-built graph is the list of scaffolds; no register of scaffolds is
  kept apart from it.
- The as-built graph's first version runs Rules, Roles and Crossing alone. **Pending**, decided by
  the author on 2026-10-24: D1 to D3 run on the as-built graph too, which find a block that needs a
  name it provides itself, as `control(organization)` needs and provides `?builder`, a loop the
  first version cannot see. It waits too on the as-built graph keeping such an edge, which it drops
  today as internal to the block.
- **The platform keeps data from the moment the as-built graph has no violation**, which is what
  the words mean. From then on, a violation on the as-built graph is refused.

**What is derived**: whether each name is provided, and by which blocks; how many samples each
component has, a component with none shown as having none; the frontier; and what is buildable.

**The frontier is every name that meets three conditions**:

1. the design graph holds it;
2. it is not yet rightly provided: it has no provider, or only providers that violate a rule on the
   as-built graph;
3. every name its hard edges point to is provided. Here a provider that violates a rule counts as
   providing, and ground, the operator and a role not yet filled count as provided. Soft edges are
   not counted, and a hard edge counts whatever its `when_`.

**What is buildable is every name whose contracts are all declared and which has samples**, the set
work may be dispatched from. It holds for a role and a boundary as for a component: the contracts
the name answers, and those on every edge pointing to it, are all declared in `model/contracts/`,
none in the undeclared form `?name`, and the name has samples. It is kept apart from the frontier:
the frontier orders what is proven, and what is buildable orders what is built.

**Thin, whole and proven are measured by samples alone, never written by hand.** A state is
judged for each provider on each target:

| State       | When                                                                        |
| ----------- | --------------------------------------------------------------------------- |
| no samples  | its interfaces have no case                                                 |
| not started | it has cases, and every one is waiting                                      |
| failing     | any case fails                                                              |
| thin        | some case passes, none fails, and some is waiting                           |
| whole       | every case passes                                                           |
| proven      | whole, and filled by a provider that violates no rule on the as-built graph |
| unknown     | its snapshot is out of date or missing                                      |

**A skipped case is not a pass**, decided by the author on 2026-10-24: it counts as one still waiting,
so whole is every case passed, as `docs/code.md` has it, "a test held back is a question, never a
pass".

**A case is given to no one component.** It is measured for each provider on each target apart,
and a component's state on a deployment is what was measured of the provider filling it there at
the time. The `samples` field a component holds by hand is not read.

**A snapshot holds what a target ran.** conform writes one snapshot for each target to
`~/.local/state/workspace/snapshots/`, never to a repository. A snapshot is bound to the commit each
component was built from, as the target itself reports it. A snapshot out of date or missing is
shown as unknown. The part of check that refuses never reads a snapshot.

**What binds a snapshot**, decided by the author on 2026-10-24: a driver answers, in management's
describe, the git revision it was built from, `revision`, given at its build as `DRIVER_REVISION`.
**A build gives one only where its source stands whole on a commit**: jj's working-copy parent
where the working copy holds no change, else git's HEAD where its tree is clean, as monoflake/driver's
`archive` reads it for a switch, a development build and a release alike; from changed source it
gives none. **Pending**: a release built by Nix from monoflake/machine's input gives that input's
revision once machine builds the driver, which waits on releases being opened. A snapshot holding the revision reports its states bound; one without falls back to the
checkout conform ran from, `checkout`, and reports them unbound.

**A block's declarations live with its code.** A block's `provides` and its extra edges are written
in the repository that holds the block's code. **A path into a sibling repository is written only in
a declaration of a dependency**: `package.json`, `Cargo.toml`, `rescript.json`, the inputs of
`flake.nix`, and a mise task's monorepo reference, `//repos/...`, which the workspace's `mise.toml`
declares through its `config_roots`. Code and tasks find a sibling repository only through what such
a declaration resolves. Prose that describes how the checkouts are laid out for development, as an
`AGENTS.md` does, is outside this rule.

**A thread's Ledger still records the provisional choices that wait on the author**, a name, a
port, a policy's value. Every entry that describes where what is built departs from the design is
removed once the as-built graph is built, and is derived from the graph from then on.

**`Steps.deployment` gains the number of machines.**

**It is done when** the scaffolds of structure the as-built graph derives and the scaffolds of
property the samples measure, a secret unsealed or a bearer's authentication, together reproduce
the inventory in RFC vgvx6's Evidence.
