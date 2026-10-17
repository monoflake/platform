---
name: 'Internal and External Platforms'
title: 'One code, the Platform, runs as two deployments: an internal platform on third-party vendors alone, pinned to a version the external platform has run, and an external platform standing on the internal one as on a vendor'
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

RFC v7v3w splits layer 0 between two halves, and RFC b8f35 stands each owner on a footing that is
ground. Worked out with the author on 2026-10-17: how the platform is built and kept running when
what it stands on must already be stable, without a cycle and without a second code to maintain.

The shape the discussion has reached so far:

**One code, the Platform, runs as two deployments at once.**

| Deployment        | Domain          | Ground                                                    | Serves                                                                  |
| ----------------- | --------------- | --------------------------------------------------------- | ----------------------------------------------------------------------- |
| internal platform | `monoflake.net` | third-party vendors alone                                 | the platform's own organizations: the console's, the external's         |
| external platform | `monoflake.com` | the internal platform's three products, and users' clouds | users, who start on the internal platform's products or bring their own |

The internal platform is internal as a company's own systems are, used by those who build the
platform and reached over the public network; it is no private network.

- **The internal platform runs a version no newer than the external's**, and keeps off by
  configuration what it does not need -- bringing one's own cloud, sharing, selling, signing up. The
  code is never forked for it.
- **The internal platform's ground is third-party vendors alone**: Cloudflare, and machines a
  provider runs. A machine the author keeps at home is bound only in the external platform, as a
  user's own cloud is.
- **The internal platform never stands on the external.** The external reaches it through layer 0's
  contracts alone, RFCs 13ixj, zn3u5 and 49qyg: to the external platform the internal one is one
  more vendor, whose formats it never reads and whose parts it never calls.
- **The boundary is the contract, never the route.** A call between the two takes the nearest way,
  RFC v7v3w -- inline, or over the loopback of a machine both run on -- through the same interface
  and the same capability checks it would meet across the world. What is forbidden is a shortcut
  around the contract: one deployment reading another's files or ports.

**The internal platform is pinned to a version the external has run.**

- Moving the pin is an upgrade by D3, one part at a time while the rest run, and it can be moved
  back, since every format is written at the lowest version its readers all read, RFC wnqvu.
- The external platform's newest version must run on the internal's pinned one, so the pin never
  falls further behind than that.
- An external-next may run ahead of the external platform, as one more organization on the internal
  one, holding the author's own organizations alone.
- What the external platform proves, the internal takes by moving its pin, so a capability is built
  once: the internal platform brings its own machines in with the code that lets a user bring
  theirs.

**A machine may run a host of each deployment**, RFC b8f35: two processes, each enrolled in its own
deployment with its own bundle, credentials and directory, sharing nothing but the machine.

- The internal platform's host is given reserved CPU and memory, so the external's cannot starve it.
- The internal platform's `instance` compute is the hosts on machines a provider runs, never a
  vendor's runtime that offers it, and stands on at least two machines, so a writer can be handed
  over when one is lost or slowed.

**The platform is built in stages, each first making the next move of the pin cheaper:**

| Stage | What                                                                                                      | Internal / external |
| ----- | --------------------------------------------------------------------------------------------------------- | ------------------- |
| 0     | v0 is installed as the internal platform by hand, the commands `scope.md` keeps for day one               | v0 / --             |
| 1     | v0 is deployed again as the external platform, an organization on the internal one                        | v0 / v0             |
| 2     | an upgrade by D3, replacing one part while the rest run, is built and proven on the external platform     | v0 / v1             |
| 3     | the pin moves to v1, by the one planned stop the bootstrap needs                                          | v1 / v1             |
| 4     | the deployer is built, taking the place of day one's commands                                             | v1 / v2             |
| 5     | the pin moves, by D3                                                                                      | v2 / v2             |
| 6     | bringing one's own cloud and more vendors than one is built, and proven on the author's own organizations | v2 / v3             |
| 7     | the pin moves: from here the internal platform stands on more vendors than one                            | v3 / v3             |

Then the loop the stages end in: built on the external platform, proven there, taken by the pin.
While the platform is built, what proves a version may take no time at all; once it serves users, it
is a release's length.

**External organizations are placed on internal ones in two stages.** An internal organization
that external organizations stand on is a **cell**.

- **Stage one: one each.** Each external organization has an internal organization of its own,
  whose footing is a vendor's database; the external organization's footing is a database of that
  internal one. A vendor's limit on how many databases an account holds is far off at this scale.
- **Stage two: a database organization.** Once the Platform replicates a tablet's log among hosts
  that offer `instance` on several machines, the internal organizations' footings become databases
  of an internal database organization, whose own footing is a vendor's. A cell then costs a tablet.
- **The quorum returns at stage two.** In v0 a tablet's log is kept in its owner's footing, RFC
  b8f35; were it still so at stage two, every footing placed on the database organization would
  write through that organization's one footing. So a tablet's log is replicated among hosts there
  instead, a capability built on the external platform first.
- **Whose footing is kept where is acyclic, and one level deep**: an organization whose databases
  are others' footings has a vendor's database as its own. A footing bound so is a resource, never
  an app's call, so RFC 49qyg's rule that no app calls an app of another organization holds.
- Moving an external organization from stage one to stage two moves only the footing beneath its
  internal organization, at most 10 GB, and the external organization sees nothing.

**An external organization crosses into the internal platform when it writes, not when it reads or
runs.** Its code runs inline in the compute the internal platform gives it; a read is served from
an instance's memory or from the internal storage through an index the compute caches, RFC b8f35;
a write is confirmed once by the internal platform as well -- a database's batch once, a journal's
segments once per write, a container once per 16 MiB.

Open, for the discussion that follows:

- How a tablet's log is replicated among hosts at stage two, simulated on paper before it is built.
- When stage two begins, and what a cell holds before it.
- A dataset policy for content already sealed above, cut, compressed and sealed by the internal
  platform no further.
- What becomes of a revoked organization's sealed data on internal organizations the platform pays
  for.
