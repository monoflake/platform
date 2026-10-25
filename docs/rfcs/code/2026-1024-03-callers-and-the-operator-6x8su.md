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

**A caller is one of eight kinds**, decided by the author on 2026-10-24, extending RFC 6dheo's
four and RFC jy0s5's component, each known by a proof of its own:

- **`host`**: a host's driver, by the one-time binding token `open` issued, which `bindings.bind`
  takes. A host has no certificate before it binds, since binding is how it joins.
- **`capability`**: an app, by a capability it carries. The gate verifies the capability is signed
  under the issuer's chain for this scope, a missing or invalid one answering `denied` and never
  falling through; what it grants is still judged inside the operation. Storage's operations take
  it. Rejected: declaring them `anyone`, which would show storage as public in the model, which it
  is not; and since an identity is not a right, RFC 6dheo, a capability is a proof of its own.
- **`authority`**: the platform half's control, by its certificate of role `authority`, which
  `notice` takes, RFC 7xpd3. It is neither an organization's control nor a component, its
  certificate's role being `authority`.

The other five stand: anyone, an account, an organization's control, the operator, and a component.

### Ledger

Choices made provisionally while the thread runs, read by the author at its end.

- **The gate's fixed order**, provisional, chosen by the advisor on 2026-10-24, reading the author's
  words "fix the authentication by order; one that needs none passes directly" as the gate's steps,
  run in this order for every call:
  1. Decode the call. Failing that answers `malformed`.
  2. Look up the operation and read the callers it declares.
  3. If the operation is declared public, it passes. No proof is read, and none is required.
  4. Otherwise the gate verifies the proof the call carries against the kinds the operation
     declares, each kind known by its own proof:
     - an account, by the call's `credential`, verified to the account key's chain;
     - an organization's control, by the call signed under a certificate of that organization;
     - the operator, by the call signed under a certificate of role `operator`, chained to the root;
     - a component, by the call signed under its instance's certificate of role `component`;
     - the authority, by the call signed under a certificate of role `authority`;
     - a host, by the one-time binding token `open` issued;
     - an app, by a capability signed under the issuer's chain for this scope.
  5. A missing or invalid proof answers `denied`. A proof that fails never falls through to a
     weaker check.

  An operation may declare several callers, provisional, chosen by the advisor on 2026-10-24,
  since several need two now, an organization's control and a component. The gate picks the check
  by the proof the call carries, a signature under a certificate of a given role, a `credential`, a
  binding token or a capability, and never tries each kind in turn.

- **The `credential` key is 5**, provisional, chosen by the advisor on 2026-10-24, the next free key
  of the call, in `monoflake:call:2`.
