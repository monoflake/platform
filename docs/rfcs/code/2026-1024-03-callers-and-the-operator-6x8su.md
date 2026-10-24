---
name: 'Callers and the Operator'
title: 'Each operation declares who may call it, one gate checks that, a call carries an account credential of its own, the operator signs by a role of its own, and an issuer serves a member'
status: accepted
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

RFC 6dheo, monoflake/cloud's, settles the platform half's own interfaces: who calls them, how an
operator is known, and how an account credential reaches each control. What it asks of this
repository's model, its signed records and its runner is written here, since they are this
repository's own, RFC 8lkuv. The call is RFC fhg6w's, its answer RFC ge55b's; who signs what is RFC
b8f35's, kept in `docs/signed.md`; the issuer is RFC vuanj's; the runner RFC p8e8k's.

## Decision

Decided by the author on 2026-10-24, in RFC 6dheo. Nothing of it is built yet.

**An interface stays in the inner call form**: `POST /{interface}/{operation}`, its body a call,
answered by an `answer`, RFCs fhg6w and ge55b. The outer `/v{n}/{scope}/...` form stays for apps
and public APIs.

**Each operation declares in the model which caller may call it**: anyone, an account, an
organization's control, or the operator.

- One gate checks that declaration, in a fixed order, before the operation runs.
- An operation anyone may call passes the gate unchecked.
- An interface is one for all its callers, so it has one version for all of them, a cost the author
  accepted.

**A call carries an account credential in a field of its own**, `credential`, optional, and the
call becomes `monoflake:call:2`.

- It never goes into `capabilities`: an identity is not a right, and one list holding both invites
  type confusion at every reader.
- The change is generated, a bump made once.

**The operator signs each call by a key of a new role, `operator`**, which the root certifies,
held offline beside the root's.

`docs/signed.md`'s table gains the root signing a certificate of `operator`, and `operator` signing
a call.

**The issuer gains an operation for a member**, beside `for_app`: an account credential, taken once
at an organization's control, exchanged for that member's capabilities.

**What a repository depending on this model fills gains `interfaces`**, `model/graph/fill.res`,
held by the subset check as a fill's types and contents are, and left out of `contracts.json`,
which holds this repository's own alone, RFC 8lkuv. Its samples are run by this repository's
runner, whose chain gains an account and the operator, RFC p8e8k.

### Ledger

Choices made provisionally while the thread runs, read by the author at its end.

- **The gate's fixed order**, provisional, chosen by the advisor on 2026-10-24, reading the author's
  words "fix the authentication by order; one that needs none passes directly" as the gate's steps,
  run in this order for every call:
  1. Decode the call. Failing that answers `malformed`.
  2. Look up the operation and read the caller it declares.
  3. If the operation is declared public, it passes. No proof is read, and none is required.
  4. Otherwise the gate verifies the one proof that declaration names: for an account, the call's
     `credential`, verified to the account key's chain; for an organization's control, the call
     signed under a certificate of that organization; for the operator, the call signed under a
     certificate of role `operator`, chained to the root.
  5. A missing or invalid proof answers `denied`. A proof that fails never falls through to a
     weaker check.

  If an operation later declares more than one caller, the gate decides by the proof the call
  carries, a signature or a `credential`, never by trying each kind in turn. Until an operation
  needs that, each declares one caller.

- **The `credential` key is 5**, provisional, chosen by the advisor on 2026-10-24, the next free key
  of the call, in `monoflake:call:2`.
