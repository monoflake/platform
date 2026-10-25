---
name: 'A binding reached by its origin'
title: "A Cloudflare binding binds by its Worker's public origin, which the control proves by calling it back, beside a machine's tunnel"
status: accepted
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

RFC rxmd9 binds a host one way. A machine's driver dials out once and calls `bindings.bind` with
its binding's token, and the control reaches it through a tunnel, at a private address it assigns.
A Worker on a bound Cloudflare account, monoflake/driver's RFC nrs5v, never dials out, has no
private address, and is served at a public origin of Cloudflare's Workers.
`binding-bind`'s input is empty, and the control's `Reach` knows only the tunnel and the relay of
the control beneath. How is a Cloudflare binding bound and reached?

## Decision

Decided by the author on 2026-10-24. **For now it is reached over the public internet**; later it
moves to a private path over Cloudflare's network, monoflake/driver's RFC 5n9cy.

- **After deploying, install binds on the Worker's behalf**: with the binding token it read on
  stdin, it calls `bindings.bind` and reports the Worker's origin.
- **`binding-bind` gains what it reaches by, as a union**, never an optional field whose absence
  means a tunnel: a tunnel, as a machine's, or an origin, an `https` URL.
- **The control verifies before it records the origin**: it calls that origin's management describe
  with the same binding token. Only a driver holding that binding's hash answers, so the origin is
  proven to be that binding's driver, and the bind succeeds only then. Without the call back,
  whoever held the token could point the control at any URL, and the control would carry the token
  there.
- **The control's `Reach` gains a direct `https` origin** beside the tunnel and the relay.
- **A control that reaches an origin declares `http` network** where it runs as an app on a machine.
- **The driver on a public URL is guarded by its `BINDING` token alone**, refusing every call without
  it, a property of the vendor, recorded as such.
- Rejected: the admin typing the URL at open, which comes before install knows it; and a tunnel in
  front of a Worker, which cannot be done.

This is the control plane alone, a control reaching a binding's driver. An app reaching its storage
on the same account is the data plane, inlined inside Cloudflare and never through the control,
the workspace's deferred `inline-data-path`.

### Ledger

Choices made provisionally while the thread runs, read by the author at its end.

- **The contract's shape**, a small matter, provisional, chosen by the advisor on 2026-10-24.
  `binding-bind` carries a union, `tunnel` or `origin`; `binding-bound` is `{binding, reached}`,
  `reached` a union; `bindings` goes 1 to 2; `bind` gains `not_proven`, rejected, a call back that
  is not that binding's driver, and a call back not reached stays `unreachable`.
- **What an origin may be**, a small matter, provisional, chosen by the advisor on 2026-10-24:
  `https`, its host a DNS name and never an IP literal, on the default port, with no path, query,
  user or fragment; anything else answers `malformed`, and samples hold each refused form. The
  control calls back whatever the binder reports, so the origin's shape is the one place to keep
  that call from being aimed at an address the control can reach and the public cannot. The
  control's own `http` network, public destinations alone, is the second guard.
- **A machine's driver moves with the control**, a small matter, provisional, chosen by the advisor
  on 2026-10-24: a driver sending the empty input of version 1 cannot bind under version 2, so the
  switch moves both machines' drivers with the control in one step, and its rollback moves them
  back together.
- **The bind samples' origins are reserved names**, a small matter, provisional, chosen by the
  advisor on 2026-10-24: `https://example.com` answers and is no driver, RFC 2606, and a `.invalid`
  name never answers, RFC 6761. The `.invalid` case needs no network; the `example.com` case does,
  so the runner marks it as needing the network and reports it skipped, never passed, where there
  is none, RFC p8e8k. The runner carries a bearer for a product's sample.
