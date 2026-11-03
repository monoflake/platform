---
name: 'How a Function Reaches a Slot'
title: "A running function reaches a slot its build declares as `env.<slot name>`, a binding speaking that kind's own contract in the same types in every home, its credential held outside the function"
status: decided
supersedes: []
references: []
---

## Question

RFC 49qyg has a build's manifest declare slots, a name and a type, `manifest-slot`, and the owner
fill them with ids, `app-bindings`, a deployment refused where the types disagree. It does not say
what a running function sees of a slot it filled, and `deployments.deploy` carries no binding, so
monoflake/driver's RFC dg903 question 3 gives a worker none of the platform's interfaces. The
reference app stops there, `code/tools/reference`, its `row written` answered 501.

## Options

- **A**: `env.<slot name>` is a binding speaking the kind's own contract, `database.execute`,
  `object.write` and the rest, in the same types in both homes. On a machine a workerd service
  reaching the driver, its credential added outside the worker; on Cloudflare a service binding to
  the driver's own object and database Workers, as plan item `inline-data-path` describes.
- **B**: `env.<slot name>` shaped as D1 and R2, emulated on a machine. Cloudflare's code runs
  unchanged, but a vendor's interface becomes the platform's, against a vendor's name staying at the
  binding edge, a large surface to emulate, and `rewind` and the limits become the vendor's.
- **C**: an address and a token in the function's environment, the function calling over HTTP. No
  new binding, but a credential in the app's memory, and on Cloudflare a data path through the
  public network, which `inline-data-path` exists to avoid.

## Decision

Decided by the author on 2026-11-03, A, asked in thread trial's decision queue.

- **A function reaches a slot as `env.<slot name>`**, the slot's name written whole as the
  manifest declares it, `env.database`, never a short form.
- **It speaks the kind's own contract**, its operations and types those of
  `model/contracts/kinds/`, the same in every home, so one build runs in both.
- **No credential reaches the function.** What lets the call through is held by the runtime the
  driver configures, outside the function's code and memory.
- Rejected: B, a vendor's interface as the platform's; C, a token in the app.

How `deployments.deploy` carries what fills a slot is a contract's shape, asked of the author apart,
in thread fifth's decision queue; until it is answered a deploy carries no slot and a function
reaches none.
