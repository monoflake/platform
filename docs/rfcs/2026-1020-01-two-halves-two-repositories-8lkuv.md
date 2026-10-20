---
name: 'Two Halves, Two Repositories'
title: 'The organization half is monoflake/platform and the platform half monoflake/cloud: the first names what it needs of the second as roles with contracts, and the second fills them, the whole model checked where both are'
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

RFC fhg6w keeps what a user runs here, MIT OR Apache-2.0, and leaves what runs it as the hosted
platform to the private `monoflake/cloud`. Code is still to be written on both sides, so each has to
make sense alone: where the line between the two repositories runs, how this one names what it needs
of the other without describing it, and how the two together still give the one model every
dimension is checked over.

## Decided

**The line is RFC v7v3w's, between the two halves**, decided by the author on 2026-10-20. This
repository holds the organization half -- an organization's control, the three products, the
primitives, the substrate and the drivers, and the app -- with the root, which runs nothing, and
every contract between the halves. `monoflake/cloud` holds the platform half -- the platform's
control, the anchor and the platform's footing -- with the console and the two deployments'
configuration, RFC 94y0d. So this repository is everything one organization needs, and the other is
what hosting many of them together adds: a team running its own writes the second as a little glue.

**What this half needs of the other is a role, named for what it does**, decided by the author on
2026-10-20: a component of a new kind, `provided`, carrying its layer, its half and the contracts it
answers, and nothing of how it is built -- no edges, no language. An edge to a role is an assumption
on its contract, as an edge to the ground is, so this repository's check runs on its own. Two roles
are needed: what the platform's control is to an organization's, RFC 7xpd3, and what the anchor is to
a scope and its backing, RFC 4dijn. Their contracts are drafts until each question below is settled,
and a role's contract left open is listed as undeclared, as one is today.

**`monoflake/cloud`'s model depends on this one's and fills each role exactly once**, by a component
of the same layer and half that implements the role's contracts, and brings its own edges,
language and records. The whole
model is the two together, a role replaced by what fills it, and is checked there by every
dimension. This repository's model names nothing only the other holds, the roles aside; what earlier
drafts here say of the platform half stays as it was written.

**The split is proven by the check, not by reading it**: the whole model's report, taken before
anything moves, is the report the two together give after, line for line.

**`monoflake/cloud` builds on a commit of this repository it names**, this checkout beside it while
both are worked on, so which version of the platform a deployment runs is a commit the other
repository records, RFC 94y0d.

**The roles are `authority` and `directory`**, decided by the author on 2026-10-20: `authority`
for what the platform's control is to an organization's, `directory` for what the anchor is to a
scope and its backing. Each answers one contract of its name, `?authority` and `?directory`, while
the platform half keeps its own -- the console's calls on the platform's control, the platform's
control's writes to the anchor -- as `?control(platform)` and `?anchor` beside them. A role is
`model/graph/components.res`'s, the roles check `model/checks/design/roles.res`, and what the other
repository gives arrives as the file `MONOFLAKE_FILL` names, `model/graph/fill.res`.

**This half knows of the other only the edges it has into a role; the other knows this half
whole, and proves those edges carried**, decided by the author on 2026-10-20. A role here is its
name, layer and half and the contracts it answers, and nothing of what it needs: how what fills it
is built, and what it stands on, is the other repository's. That repository imports this model's
edges into the roles and proves each in its own flow -- a component of its own fills the role,
implements every contract the edge names, and stands, on the whole graph, without the component
the edge comes from, `model/proof.res` there -- while the whole graph's cycles and every dimension
are checked where both are.

**What crosses the line is public, and how it is made is not**, decided by the author on
2026-10-20. Of the platform half's records an organization's half reads two: an organization's,
what the authority alone decides of it, and an account, known here by its id and the signed
account credential, RFC b8f35, and by nothing of its own record. The account's record and the seven
others the platform's control alone keeps -- its extension, loan, label, username, sign-in,
membership and domain -- are monoflake/cloud's, and `contracts.json`, which every language reads,
is written from this repository's own alone.

**The rest of the line runs the same way**, decided by the author on 2026-10-20. The reserved
names stay here, since an organization's control refuses them for a mount as the platform's does
for a label. What each version of the Platform can do is the code's, and stays; the bootstrap path
-- each step's deployments, their ground and plan, how each came to it -- is how the hosted
platform is stood up, and is the other repository's, with the checklist's group D, its commercial
and operational questions. Checked alone, this repository reads no path and accepts a mark naming a
row of group D; a row of group C is held to a step where the path is.

**The proof held on 2026-10-20**: with the graph walked by name, so no order rests on where a part
is declared, the whole model's report from both repositories is the report before the split, line
for line, but for the roles check, the two contracts each split in two, and one list of declared
records now given in two parts.
