---
name: 'Paths in the Bundle'
title: 'The bundle names each path from a caller by its jumps and whether it crosses the public network, fewest jumps first'
status: decided
supersedes: []
references: []
---

## Question

RFC ot812 left the paths in the bundle open until the host was settled, and RFC tkil2 proposed them
among what the host leaves open. What does a bundle say of the ways from a caller to each host, and
in what order?

## Options

- Name each path by the jumps it crosses and whether it crosses the public network, ordered as RFC
  vr5lw orders reaching a host, as tkil2 proposed.
- Name a host alone and leave the route to the caller, which then has to learn the networks itself.

## Decision

Decided by the author on 2026-11-01, tkil2's proposal for this section alone, the rest of tkil2
staying a draft. `bundle-host` gains `paths`, from each caller's extension by its id to the paths
from it. A path is the jumps it crosses in order, by their extensions' ids, and whether a network
it crosses is the public one. No jump is within a host, so a caller's own host is reached by no
jump and off the public network, and a host no network reaches has no path. Paths are ordered
fewest jumps first, then one off the public network first, as RFC vr5lw orders them, then by their
jumps' ids compared in turn. `extensions*` computes them, RFC kd7f9. The lender's own record of a
loan stays RFC 87lwb's.
