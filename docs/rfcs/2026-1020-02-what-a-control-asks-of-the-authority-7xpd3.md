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

## Open, for the discussion that follows:

- How the organization's control proves who it is to the role, and how it knows an answer is the
  role's: records signed beneath the root, RFC b8f35, or the connection alone. [B37]
- The least a role must do for a platform of one organization -- one certificate, an allowance
  without bounds, no loans -- which is the glue a team running its own writes. [B38]
