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
- **The call back waits 10 seconds and never follows a redirect**, a small matter, provisional,
  chosen by the advisor on 2026-10-24.
- **The runner runs as if there were no network unless told otherwise**, a small matter,
  provisional, chosen by the advisor on 2026-10-24: with no `--network`, a case needing the network
  is skipped, each named with its reason and the count skipped printed beside the count passed;
  only `--network yes` runs them. A probe that decides by itself gives a result that depends on the
  room it runs in and proves nothing of the target, so none is built.
- **An origin's host is judged as the WHATWG parser leaves it**, a small matter, provisional, chosen
  by the advisor on 2026-10-24, the parser a Worker's `URL` uses, so hex, octal and dotless IPv4
  forms are normalized before they are judged, and a trailing dot and punycode are judged in their
  parsed form. `localhost`, `.local`, `.internal`, `home.arpa` and a host whose last label is a
  number are refused too, for the reason an IP literal is: the call back must go only where the
  public reaches.
- **A step runs as the operator only on an operation the model declares the operator's**, a small
  matter, provisional, chosen by the advisor on 2026-10-24, today bindings' `open`, every other
  refused, the set read from the model's callers, RFC 6x8su, never kept as a list in the runner.
- **A run is told its organization**, a small matter, provisional, chosen by the advisor on
  2026-10-24: `--organization` is required by any selected case using the run's organization, and
  the runner refuses before running anything where it is missing, naming those cases. It never opens
  an organization on the control under test.
- **A binding's reach is fixed by its first successful bind**, a small matter, provisional, chosen
  by the advisor on 2026-10-24: after a tunnel bind an origin bind is refused, and the other way
  round, answering `invalid`, so deploy, describe, the gateway and the relay never disagree about
  where a binding lives.
- **An origin binding's token is spent on `bind` by its first successful bind**, a small matter,
  provisional, chosen by the advisor on 2026-10-24, after the author's own word, a host known by
  "the one-time binding token `open` issued", RFC 6x8su. A second bind with it answers `denied`, and
  moving an origin binding to another origin takes the operator opening it again, never the token
  alone; so a token's holder cannot carry a bound binding off to a server of their own, nor two
  holders flip it. The call back proves the origin answers, never who holds the token. The token
  stays the secret the control presents to the binding's driver on every call.
- **The gateway and the relay answer `beyond_host` for an origin binding**, a small matter,
  provisional, chosen by the advisor on 2026-10-24: its data plane never passes through the
  control, monoflake/driver's RFC nrs5v and the workspace's deferred `inline-data-path`, so they
  guess no path. Storage places nothing on such a binding either, choosing only a binding with an
  address, until that path lands.
- **Cloudflare's own 521 to 524 and 530 on the call back answer `unreachable`**, a small matter,
  provisional, chosen by the advisor on 2026-10-24, as the issuer's do; `not_proven` is only for an
  origin that answered and is not that binding's driver. A failed call back answers a fixed message,
  never the fetch's own text.
- **A name resolving to a private address passes the form check**, a fact recorded by the advisor on
  2026-10-24, a wildcard DNS service's name for a loopback address among them: the runtime stops it,
  Cloudflare's edge for a control on Cloudflare and workerd's `allow = ["public"]` for a control
  running as an app with `http` declared, which the run sheet checks.
- **A tunnel binding's `bind` accepts its token again**, provisional, chosen by the advisor on
  2026-10-24, a scaffold of property against the one-time token: today only the operator runs it
  again by hand, through monoflake/cloud's bind script. A bind again answers the tunnel's
  credentials, so a token's holder could take a tunnel binding's traffic too. The extra risk is
  small today, since the same token already lets its holder speak to the driver as the control, a
  leaked token being the whole compromise already. It retires once a bound host is known by a
  certificate of its own, RFC b8f35, a bind again then proven by that certificate and the binding
  token no longer the control's secret toward the driver.
- **A kind's interface declares `component` that no driver accepts yet**, provisional, chosen by
  the advisor on 2026-10-24, a scaffold of property retiring with RFC 6x8su's gate: `object`,
  `deployments` and `database` declare `component` among their callers, while both drivers accept
  only the binding's token. The path RFC b8f35 describes, the blob and the extent moving parcels
  through the object kind under a certificate, does not exist yet.
