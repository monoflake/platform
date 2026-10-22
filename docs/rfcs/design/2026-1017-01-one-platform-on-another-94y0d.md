---
name: 'One Platform on Another'
title: "A platform may stand on another's three products as on any vendor: one code, never forked, each platform knowing itself alone, the one above handing the one below only what it sealed"
status: landed
supersedes: []
blocked-by: []
commits:
  - monoflake/platform@8fa730b6
  - monoflake/platform@2bb67dec
  - monoflake/platform@3dd9d5dc
  - monoflake/platform@06c72d7f
references: []
---

## Question

RFC v7v3w splits layer 0 between two halves, and RFC b8f35 stands each owner on a footing that is
ground. Worked out with the author on 2026-10-17: how a platform is built and kept running when
what it stands on must already be stable, without a cycle and without a second code to maintain.
How the hosted platform uses what is decided here is the platform half's, RFC 8lkuv.

## Decision

**One code, the Platform, may run as more than one deployment, and one may stand on another's three
products as on any vendor.**

- **The code is never forked for a deployment**: one keeps off by configuration what it does not
  need -- bringing one's own cloud, selling, signing up.
- **The one beneath never stands on the one above.** The one above reaches it through layer 0's
  contracts alone, RFCs 13ixj, zn3u5 and 49qyg: to it the one beneath is one more vendor, whose
  formats it never reads and whose components it never calls.
- **The boundary is the contract, never the route.** A call between the two takes the nearest way,
  RFC v7v3w -- inline, or over the loopback of a machine both run on -- through the same interface
  and the same capability checks it would meet across the world. What is forbidden is a shortcut
  around the contract: one deployment reading another's files or ports.

**A platform knows itself alone**, decided by the author on 2026-10-20: another platform is outside
it, whether or not it runs the same code, so nothing of one platform's records names the other's,
and nothing checks across them. **Between two platforms are an export and an import, each bounded
by its own side**: the importing platform binds what it takes as an extension, held to that
extension's quota, RFC v7v3w; the exporting platform holds what each of its organizations may give
out by the `export` capability of its allowance, RFC 49qyg, which its own control enforces. What
exports is an app of the exporting organization's own, a driver's contract its interface, RFC
vr5lw, so the importing platform binds it as it binds any vendor, and a cell is an extension's host
to it, known by an identifier it never reads. The exporting platform bears its exports' bounds, and
the importing platform never sees past them.

**A machine runs one driver, which may serve bindings of more than one platform**, RFC v7v3w, each
with its own bundle, credentials and directory, sharing nothing but the machine; what it runs for
the platform beneath is given reserved CPU and memory, so the one above cannot starve it.

**A platform meters what it uses before others' code runs on it**: a vendor offers no hard cap, so
it counts what it uses of each resource and cuts its own use off short of a limit it sets, with a
margin. The cutoff is soft: a little may pass it, and what it holds back is the growth that lasts.
Once it holds, a vendor's primitive priced by use, Durable Objects among them, may be used as well.
**A machine is metered as a vendor is**: what it sends and receives, and its disk, which the
platform limits below what the machine has, so a write is refused by the platform and never by a
full file system.

**The organizations of the platform above are placed on the one beneath's in one of two ways.** An
organization beneath that the one above's organizations stand on is a **cell**.

- **One each.** Each organization above has a cell of its own, whose footing is a vendor's
  database; the organization's footing is a database of its cell.
- **A database organization.** The cells' footings are databases of a database organization
  beneath, whose own footing is a vendor's, each a tablet on machines kept by a majority of its
  copies, RFC vuanj. A cell then costs a tablet, and its footing writes nothing through the database
  organization's own, which a tablet's copies reach only to take a primary over. **No version waits
  on it**, decided by the author on 2026-10-20: a tablet's copies are v0's.
- **Whose footing is kept where is acyclic, and one level deep**: an organization whose databases
  are others' footings has a vendor's database as its own. A footing bound so is a resource, never
  an app's call, so RFC 49qyg's rule that no app calls an app of another organization holds.
- Moving an organization from the first to the second moves only the footing beneath its cell, at
  most 10 GB, and the organization sees nothing.

**The platform above hands the one beneath only parcels it has sealed**, whatever its own buckets
ask: each is put whole into an `opaque` bucket of the organization's cell, a bucket per placement,
RFC 13ixj, so nothing is cut, compressed or sealed twice. An organization's footing above is a
database beneath and is sealed there, since it holds the bundle that opens the parcels.

**The platform above is its cells' admin**, and sets their buckets' policies downward as any owner
does, the upper writing into a format the lower defines, `docs/scope.md`. A change to a bucket's
policy above is its own migration; the one beneath sees only parcels written and deleted. **An
organization revoked above is suspended, and so is its cell**; both are deleted seven days after
unless restored, RFC b8f35, so the platform pays for what it sealed no longer than that.

**An organization above crosses into the one beneath when it writes, not when it reads or runs.**
Its code runs inline in the compute the one beneath gives it; a read is served from an instance's
memory or from the storage beneath through an index the compute caches, RFC b8f35; a write is
confirmed once beneath as well -- a database's batch once, a journal's segments once per write, a
parcel once per 16 MiB.
