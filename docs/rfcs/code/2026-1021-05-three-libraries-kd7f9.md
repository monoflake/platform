---
name: 'Three Libraries'
title: 'The interfaces of vocabulary*, wit* and extensions*: what each computes, pure, of what its caller hands it'
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

`model/graph/libraries.res` names three libraries the control, compute, the issuer, the executor
and the host use, and says in a line what each is; their interfaces, which the model owns, are
unwritten. What each must do is settled across RFCs 49qyg, vuanj, v7v3w and vr5lw; what is left is
the shape, and where that shape stops.

## Proposed

Written by the agent on 2026-10-21 for the author to decide. Each is pure: it reads what its caller
hands it, decoded by `envelope*`, and reaches no store, no clock and no network, so every reader in
both runtimes judges alike.

1. **vocabulary\*, capabilities by name, type and rule**, RFC 49qyg: one table of entries, each a
   name, a type -- yes or no, an amount, one of a set, some of a set, as `allowance-value` holds
   them -- a rule and a default; the entries settled today, `kind`, `network`, `instance` and
   `export`, and one more added later changing nothing that compares. Two comparisons, each naming
   the capability that fails: `fits`, a need against an allowance, which the control runs as a
   change gives an app a version and `scope*` as a reader judges a need; and `meets`, a need
   against an offer, which the executor and placement run to choose a host. Defaults are filled
   before either, so an absent need is its default's.
2. **wit\*, an export's types and a call checked against them**, RFCs 49qyg and vr5lw: WIT read from
   a build manifest's `wit`, the component model's language as far as the subset taken; the
   exports and their signatures; a call matched to the export it names by its parameters' number
   and types, never their values; an export removed or changed that something calls, named; and a
   value converted between its JSON and its CBOR by the type both ends hold, as vr5lw's table writes
   each, refused where it does not parse as that type. The control runs the change-time checks and
   compute the conversion; cycles stay the control's.
3. **extensions\*, a control's extensions**, RFCs v7v3w and vr5lw: what both controls compute alike
   of the `extension` and `capacity` records -- a binding made from its host, its levels and place
   copied; its grace and quota in force, the organization's where its own is unset; the levels a set
   of members compose to, from those at `stable` and above; the `management-apply` a list of
   capacity becomes, each credential hashed; a loan's two records; and the paths to each host,
   fewest jumps first, for the bundle. Sealing, tokens and every call stay in the control.

## Open

The WIT subset's resources, `own` and `borrow`; the capabilities past those four, C11; an
export's amounts, C37; what a host offers, which waits on `?roster`. Each is a field or an entry
added, not a change of these shapes.
