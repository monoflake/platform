---
name: 'What a Control Asks of the Authority'
title: "The contract between an organization's control and the role above it, which says the organization exists, certifies its key, sets its allowance and lends to it"
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

RFC 8lkuv names the platform's control, as an organization's control needs it, a role of its own,
since the platform half is another repository's. The edge is drawn today -- an organization's
control copies down its certificate, allowance and loans each day and on a change, RFC v7v3w -- but
its contract is undeclared, `?control(platform)`. Whatever is decided here is what a team running
its own platform writes as glue, so how small that glue can be is decided here too.

What the role does for one organization is settled by the drafts already: it opens, suspends,
restores and deletes the organization, certifies its key under the intermediate, sets its allowance,
RFC vuanj, and lends it what it binds, RFC v7v3w. What is not settled is what crosses.

## Decided

**What the authority decides of an organization travels one way, pulled by the organization's
control**, decided by the author on 2026-10-20: the control pulls once when it holds nothing yet,
and again whenever the authority notices it of a change. A notice is a call the other way that
carries nothing but that there is something to pull, as a webhook does; the data never moves but
by the pull. So an idle platform sends nothing between the two, and a team running its own writes
the authority as the pulled end, noticing the control as it changes something.

**What is pulled is one record the authority signs**, decided by the author on 2026-10-20: the
organization's certificate, its allowance, its loans and its status. Its salt and key are no part
of it: they are delivered once, at opening, as every secret is.

**A notice is sent again until it is pulled, and a pull is the one answer to it**, decided by the
author on 2026-10-20: a notice names the generation there is to pull, and the authority repeats it
until it sees the organization's control pull that generation or a later one. **With no notice,
the control pulls only before its certificate expires**, which the certificate carries. **While
the authority cannot be reached, the organization serves on from the last record it pulled** until
that certificate expires: what is lost meanwhile is a change to it, never what it serves, as the
data plane runs on while a control is lost, `docs/scope.md`. How long a certificate lives is the
operator's to set, and so the hosted platform's. [D17]

**Trust rests on signatures, never on the connection**, decided by the author on 2026-10-20. The
record pulled is signed by the authority under a key the intermediate certified, in a chain to the
root, RFC b8f35, so the control knows it as the authority's whatever carried it. The control signs
its pull with the organization's own key, which it holds from opening, so even its first pull says
who it is, and no secret is shared between the two. A notice is not signed: it carries nothing but
a generation, so a false one costs one pull, which is signed, and the control limits how often it
is called.

**The authority certifies the organization's working keys too**, decided by the author on
2026-10-20, as the intermediate did: the key an organization's issuer signs with, and the key its
control signs its bundle with, each certified in a chain to the root and renewed before it expires,
RFC v7v3w. The intermediate is how the authority does it, the platform half's, and an edge of this
half to it is an edge to the authority.

**The least an authority does, for a platform of one organization, is the glue a team running its
own writes**, decided by the author on 2026-10-20: a root of its own, kept offline, certifying the
key the authority signs with; at opening, the organization's key and salt, delivered once; the
pulled end, answering a signed pull with the organization's certificate, an allowance without
bounds, no loans and its status; the organization's working keys, certified as they are renewed;
and an account credential signed for each person who signs in,
however they sign in. It need send no notice: with nothing changing, the control pulls only before
its certificate expires.

**No authority is published, only the cases it is held to**, decided by the author on 2026-10-20:
a reference authority would be the glue itself, so this repository gives the contract and, with it
once declared, its cases in `tests/kinds/`, against which a team checks the authority it writes.
