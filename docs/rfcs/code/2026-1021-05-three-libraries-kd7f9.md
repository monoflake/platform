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

## Decided

Decided by the author on 2026-10-21, from the agent's proposal and in the author's own words where
they differed from it. The interfaces are the libraries' own `.resi` files, which the model names.

- **Each is pure, as code a WebAssembly sandbox could run is**: it reads what its caller hands it,
  decoded by `envelope*`, and reaches no store, no network, no clock and no source of randomness;
  a moment it judges at, a grace period's end or a quota in force, is an argument its caller
  passes, so every reader in both runtimes judges alike.
- **vocabulary\*, capabilities by name, type and rule**, RFC 49qyg: one table of entries, each a
  name, a type, yes or no, an amount, one of a set, some of a set, as `allowance-value` holds them,
  a rule and a default; the entries settled today, `kind`, `network`, `instance` and `export`, and
  one more added later changing nothing that compares. Two comparisons: `fits`, a need against an
  allowance, which the control runs as a change gives an app a version and `scope*` as a reader
  judges a need; and `meets`, a need against an offer, which the executor and placement run to
  choose a host. Defaults are filled before either, so an absent need is its default's, and a
  comparison that fails names every capability that fails, not the first alone.
- **wit\*, an interface's definition and the one layer of dependency a deployment checks**, RFCs
  49qyg and vr5lw: WIT read from a build manifest's `wit`, the component model's language as far as
  the subset taken; the exports and their signatures; and, as an app is deployed, each call it
  makes matched to an export its own dependencies provide, by its parameters' number and types and
  by every case the export's result or variant names being one the caller's type holds, never by
  values. It looks one layer down and no further: a dependency's own dependencies
  are checked when that dependency is deployed, and what an export does behind its definition,
  whether it is right or runs at all, is no part of it. Converting a value between its JSON and its
  CBOR by the type both ends hold is compute's, at run time, with the types `wit*` reads; cycles
  stay the control's.
- **extensions\*, a control's extensions**, RFCs v7v3w and vr5lw: what both controls compute alike
  of the `extension` and `capacity` records, a binding made from its host, its levels and place
  copied; its grace and quota in force, the organization's where its own is unset; the levels a set
  of members compose to, from those at `stable` and above; the `management-apply` a list of
  capacity becomes; a loan's two records; and the paths to each host, fewest jumps first, for the
  bundle. Each credential reaches it already hashed: the control makes and hashes it beside its
  sealing and its tokens, so `extensions*` never holds a secret.

- **A rule follows its entry's type**, decided by the author on 2026-10-22 from the agent's
  proposal, so no entry writes one of its own: a flag needed holds only where the other side holds
  it; an amount is at most the other side's; one of a set is a member of the other side's set, an
  allowance or an offer holding `some`; some of a set is a subset of the other side's. `kind` is
  then one of `derive` and `effect`, its allowance some of them, both by default; `export` is a
  group of amounts, each at most the allowance's.
- **A sandbox is an entry of the vocabulary**, one of a set, decided by the author on 2026-10-22, so
  what a host offers is compared by the same rules as every other entry.
- **An organization holds a quota, and a binding's unset one is the organization's**, decided by
  the author on 2026-10-22: the `organization` record gains a `quota` beside its `grace`.
- **The WIT a manifest carries is one file**, decided by the author on 2026-10-22 from the agent's
  proposal: an optional `package` line, `interface` blocks of `type`, `record`, `variant`, `enum`,
  `flags` and `func` items, a `use` of an interface in the same file, and one `world` exporting
  those interfaces or functions; `resource`, `own`, `borrow`, `include` and a `use` or `import` of
  another package refused as the WIT is read, until the subset grows.

## Open

The WIT subset's resources, `own` and `borrow`; the capabilities past those four, C11; an
export's amounts, C37; what a host offers past the sandbox, which waits on `?roster`. Each is a
field or an entry added, not a change of these shapes.

- **The paths in the bundle**: `bundle-hosts` holds each host's `relays` and `address` and no path,
  so the shape the paths take there is not written; nor is the lender's own record of a loan. The
  author decided on 2026-10-22 that it waits for the host to be written.
