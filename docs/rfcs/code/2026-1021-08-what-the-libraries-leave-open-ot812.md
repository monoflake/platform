---
name: 'What the Libraries Leave Open'
title: "What the three libraries still wait on: WIT's resources, the capabilities and an export's amounts past those settled, a host's offer past its sandbox, and the paths in the bundle"
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

Left open by RFC kd7f9.

The WIT subset's resources, `own` and `borrow`; the capabilities past those four, C11; an
export's amounts, C37; what a host offers past the sandbox, which waits on `?roster`. Each is a
field or an entry added, not a change of these shapes.

- **The paths in the bundle**: `bundle-hosts` holds each host's `relays` and `address` and no path,
  so the shape the paths take there is not written; nor is the lender's own record of a loan. The
  author decided on 2026-10-22 that it waits for the host to be written.
