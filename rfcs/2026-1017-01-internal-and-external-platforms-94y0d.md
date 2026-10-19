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
  configuration what it does not need -- bringing one's own cloud, selling, signing up. The
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

**A machine runs one driver, which may serve bindings of both deployments**, RFC v7v3w, each with
its own bundle, credentials and directory, sharing nothing but the machine.

- What the driver runs for the internal platform is given reserved CPU and memory, so the
  external's cannot starve it.
- The internal platform's `instance` compute is the hosts on machines a provider runs, never a
  vendor's runtime that offers it, and stands on at least two machines, so a writer can be handed
  over when one is lost or slowed.

**The platform is built in steps, each first making the next move of the pin cheaper**, and
`model/bootstrap.res` checks every step and every move, `scope.md`:

| Step | What                                                                                                                  | Internal / external |
| ---- | --------------------------------------------------------------------------------------------------------------------- | ------------------- |
| 0    | v0 is installed as the internal platform, its own half by the commands `scope.md` keeps for day one, its hosts bound  | v0 / --             |
| 1    | v0 is deployed again as the external platform, an organization on the internal one                                    | v0 / v0             |
| 2    | an upgrade by D3 is built, and the external platform moved to it by a planned stop of its own                         | v0 / v1             |
| 3    | the pin moves to v1, by the internal platform's one planned stop                                                      | v1 / v1             |
| 4    | the deployer is built, taking the place of day one's commands                                                         | v1 / v2             |
| 5    | the pin moves, by D3                                                                                                  | v2 / v2             |
| 6    | bringing one's own cloud, more vendors than one, and metering are built, and proven on the author's own organizations | v2 / v3             |
| 7    | the pin moves: from here the internal platform survives losing a vendor, and meters what it uses                      | v3 / v3             |
| 8    | others than the author and a friend or two are invited to test, a checkpoint, once metering holds                     | v3 / v3             |
| 9    | a tablet's log replicated among hosts is built, and proven on the external platform                                   | v3 / v4             |
| 10   | the pin moves: cells move onto a database organization                                                                | v4 / v4             |

- **The bootstrap stops twice, and only then**: each deployment once, moving from v0, which cannot
  replace a part while the rest run. The external platform's stop comes first, while only the
  author's organizations are on it.
- **Only the platform's own half is installed by hand**, worked out with the author on 2026-10-19:
  the operator deploys the platform's control and footing and opens the internal platform's
  organization through the control's API; every host after is bound as any host is, by a token its
  control makes and a command or secret the operator enters, RFC vr5lw, so day one runs the code a
  user's binding runs and no path used once. The platform's own vendor accounts are never bound,
  RFC v7v3w, which is why they alone are by hand.
- **Step 0 binds three machines**: two of four cores and 24 GB, the two `instance` needs so a
  writer is handed over when one is lost, and one of 1 to 2 GB, since most machines a small team
  brings are that size, and a driver that fails on one should fail on day one. The author holds
  about ten more, kept for the steps that ask for them.
- **The vendor's paid plan is held from step 0**: the author took Cloudflare's on 2026-10-19, $5 a
  month and use past it, which brings D1 at 10 GB and CPU time past 10 ms, `lessons.md`; more is
  bought as use grows, by those who use it. So the storage cuts and seals in a Worker from the
  start, and a machine at step 0 is there for `instance` alone.
- **Others are invited only once metering holds**, worked out with the author on 2026-10-19: while
  only the author and a friend or two use it, what the plan bills past its base is the author's own
  use, and nothing counts it. A vendor offers no hard cap, so before others' code runs on the
  platform, it counts what it uses of each resource and cuts its own use off short of a limit it
  sets, with a margin. The
  cutoff is soft: a little may pass it, and what it holds back is the growth that lasts. Once it
  holds, a vendor's primitive priced by use, Durable Objects among them, may be used as well.
- **A machine is metered as a vendor is**: what it sends and receives, and its disk, which the
  platform limits below what the machine has, so a write is refused by the platform and never by a
  full file system.

Then the loop the steps end in: built on the external platform, proven there, taken by the pin.
While the platform is built, what proves a version may take no time at all; once it serves users, it
is a release's length.

**External organizations are placed on internal ones in two ways, one after the other.** An internal
organization that external organizations stand on is a **cell**.

- **First, one each.** Each external organization has an internal organization of its own,
  whose footing is a vendor's database; the external organization's footing is a database of that
  internal one. A vendor's limit on how many databases an account holds is far off at this scale.
- **Then, a database organization.** Once the Platform replicates a tablet's log among hosts
  that offer `instance` on several machines, the internal organizations' footings become databases
  of an internal database organization, whose own footing is a vendor's. A cell then costs a tablet.
- **The quorum returns with the database organization.** In v0 a tablet's log is kept in its owner's
  footing, RFC b8f35; were it still so then, every footing placed on the database organization would
  write through that organization's one footing. So a tablet's log is replicated among hosts there
  instead, a capability built on the external platform first.
- **Whose footing is kept where is acyclic, and one level deep**: an organization whose databases
  are others' footings has a vendor's database as its own. A footing bound so is a resource, never
  an app's call, so RFC 49qyg's rule that no app calls an app of another organization holds.
- Moving an external organization from the first to the second moves only the footing beneath its
  internal organization, at most 10 GB, and the external organization sees nothing.

**The external platform hands the internal one only parcels it has sealed**, whatever its own
buckets ask: each is put whole into an `opaque` bucket of the external organization's internal
one, a bucket per placement, RFC 13ixj, so nothing is cut, compressed or sealed twice. The external
organization's footing is a database of the internal one and is sealed there, since it holds the
bundle that opens the parcels.

**The external platform is its internal organizations' admin**, and sets their buckets' policies
downward as any owner does, the upper writing into a format the lower defines, `scope.md`. A change
to an external bucket's policy is the external platform's own migration; the internal one sees
only parcels written and deleted. **An external organization revoked is suspended, and so is
the internal organization beneath it**; both are deleted seven days after unless restored, RFC
b8f35, so the platform pays for what it sealed no longer than that.

**Once a deployment runs a version that replaces a part while the rest run, it never stops again on
the correct path**, and the bootstrap stops at most five times; `model/bootstrap.res` checks both. A
stop after that is a failure, which the correct path cannot produce: a capability proven too
briefly on the external platform and taken by the pin, say, which a later stage of the model takes
in.

**An external organization crosses into the internal platform when it writes, not when it reads or
runs.** Its code runs inline in the compute the internal platform gives it; a read is served from
an instance's memory or from the internal storage through an index the compute caches, RFC b8f35;
a write is confirmed once by the internal platform as well -- a database's batch once, a journal's
segments once per write, a parcel once per 16 MiB.

Open, for the discussion that follows:

- How a tablet's log is replicated among hosts, simulated on paper before it is built. [C1]
- What metering counts for each vendor and machine, where the counts are kept, and the margin it
  cuts off at. [C18]
- When cells move onto a database organization, and what a cell holds before. [C6]
