---
name: 'One Way Between Organizations'
title: 'The only boundary between organizations, and between platforms, is the public network over HTTPS: nothing is inlined across it, and the one way over is an export imported'
status: accepted
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

RFCs 49qyg and v7v3w have no app call an app of another organization: an organization that wants
another's app reaches it as a third party does, the other exporting a public API and the caller
reaching it as an `effect`, its `unavailable` the caller's to handle. RFC 94y0d lets one
organization's database be another's footing as a bound resource, never an app's call, acyclic and
one level deep, the boundary the contract and never the route. RFC vr5lw has a call take the fewest
jumps, within a host the platform's to take. None of them says whether a path may be inlined across
organizations that share a platform, a vendor account or a machine, or whether two control planes
may talk by an internal path.

## Decision

Stated as a rule by the author on 2026-10-24. It extends RFCs 49qyg, v7v3w, 94y0d and vr5lw, which
are landed and stand as written; where they leave a path within one platform or one host open, this
closes it between organizations.

1. **Nothing is inlined across organizations.** Even where two organizations' things run on one
   platform, one vendor account or one machine, no internal path joins them. Inlining, RFC vr5lw's
   fewest jumps and RFC 94y0d's inline or loopback, holds within one organization alone.
2. **The one way across is export, then import.** An organization explicitly exports a capability
   at a public HTTPS endpoint, which anyone may then call as a public service; another organization
   uses it as it would any vendor's, as an `effect`, or imported as its ground. The boundary is cut at
   that public endpoint.
3. **The control plane is held to it too.** Two organizations' control planes, even on one
   platform, talk over public HTTPS, each side presenting its own credential.
4. **HTTPS only**, with no plain-text exception on any crossing: TLS encrypts, and each side's
   credential authenticates.

It makes plain that a platform reaching its footing through the relay of the platform beneath it is
exactly the internal shortcut this forbids, which RFC btzlt's check already reports as against RFC
94y0d; the way out is the platform beneath exporting it publicly and the one above importing it.

**What the model holds of it.** Between platforms, RFC btzlt's checks: a name a column takes from
beneath must be a product at layer 0 answering every contract of the name it fills, and an edge
marked `beneath` is judged by the products alone. Between organizations nothing is held yet, since
the model reads one organization at a time; the check waits on the model holding an import, a
deployment's name filled by another organization's export, and is Pending until then.
