---
name: 'An App on a Binding of Functions'
title: 'What an app is on a binding whose driver offers functions and objects and no container'
status: accepted
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

The control's `releases.deploy` deploys an app into a container item it asks of the binding's
driver, made where the binding holds none, `code/products/control/src/api/deploying.res`. A binding
whose driver offers the function and object kinds alone, as driver(cloudflare) does on a Cloudflare
account, has no container to give, so no app can be deployed onto it. What is an app there, and
what does `releases.deploy` ask of such a binding.

## Options

What the decision below leaves open, each with the integrator's recommendation, proposed on
2026-10-26 and open until settled:

- **The key in `metadata.json` is `kinds`**, a JSON array of kind names in the order the code
  prefers, as `"kinds": ["function"]`. A bundle's `metadata.json` is the deploy tool's own, written
  from the app's wrangler configuration, so the app writes its declaration in a `metadata.json` of
  its own beside that configuration, holding `kinds` alone. The tool reads that member only and
  writes it into the bundle's `metadata.json` beside `main_module`, so the declaration is inside the
  artifact's hash and one hash has one declaration. A component declares the same member of its
  `metadata.json` once a builder for components lands.
- **An image declares them in the label `monoflake.kinds`**, the names joined by commas in the
  order the code prefers, as `container`. The label's key names no domain, since the platform's are
  withheld from this repository, `model/names/withheld.res`, and `MONOFLAKE_` already names what
  the platform hands a deployment, y2xd3.
- **The tool refuses a declaration it cannot read whole**, before wrangler builds or anything is
  put: a kind it does not know, an empty list, or a kind named twice, as `metadata.json declares
  kind vm, not function, instance or container`. A kind dropped quietly would deploy the code where
  it did not say. A declaration absent sends no `kinds`, read by its form below.

## Evidence

- On 2026-10-25 hello was deployed through a control onto a binding of driver(cloudflare) offering
  `function,object`, right after that driver's install. The control drew the app's id and the
  driver refused the list: `beyond_host: app 23f191e8, item 1: a Worker's account holds no
  container or volume`. Nothing was made on the account, and the app's row stays with no container
  until releases can forget it.
- The previous control asked the same container item, so this is not the bare ids' doing.
- driver(cloudflare) deploys a function as a Worker of its own, monoflake/driver's RFC nrs5v; the
  control's app path never asks that kind.
- On a machine an app is already a function: driver(machine) deploys modules for workerd by its
  function kind, inside the binding's container of capacity, monoflake/driver's RFC dg903 and
  `machine/src/served.rs`. The container item the control asks is that capacity, not the
  container kind, so hello, B and every app deployed so far run as functions.
- Both drivers answer the kinds they offer in management's describe, `management-described`'s
  `kinds`, vbg0u: driver(machine) function, container, object and volume, its instance waiting on
  dg903; driver(cloudflare) what its install chose, function and object on the binding hello was
  refused on.
- A bundle's `metadata.json` is written by the deploy tool from `wrangler.json` or
  `wrangler.jsonc`, `code/tools/deploy/src/bundle.res`, and wrangler 4.151.3 warns at a top-level
  field of its configuration it does not know. Both drivers read only the members of
  `metadata.json` they know, `cloudflare/function/src/archive.res` and
  `machine/function/src/bundle.rs`, and driver(cloudflare) writes Cloudflare's metadata field by
  field, so a `kinds` member never reaches Cloudflare.

## Decision

Decided by the author on 2026-10-25: **an app is matched to a binding by kind**. Code declares the
kinds it can run as, never a place or a vendor; a binding's driver declares the kinds it offers;
the control deploys where the two meet. The compute kinds are function, instance and container,
RFC vr5lw.

1. **The code declares its kinds in its own directory**, decided by the author on 2026-10-26, never
   by a flag of the deploy, which whoever deploys it would declare instead. Modules and a component
   declare them in their `metadata.json`, an image in a label. The deploy tool reads the
   declaration and carries it into `release-put`'s optional `kinds`, a list of a new enum
   `deployment-kind`, function, instance and container, declared in
   `model/contracts/kinds/deployments.res` beside `deployment-form`, releases moving to version 6
   in `model/contracts/products/releases.res`. The control keeps them with the release,
   `code/products/control/src/parts/state.res`'s release row and a migration, and never opens the
   artifact to learn them.
2. **The release's order is the preference**, provisional, chosen by the advisor on 2026-10-26:
   the first of its kinds the binding offers is chosen. The binding's kinds are a set,
   `management-kind` unordered, and only the code knows which way it runs best.
3. **No kind shared is `beyond_host`**, provisional, chosen by the advisor on 2026-10-26, a reason
   `releases.deploy` already answers: `release <hash> runs as function, and binding <8 hex> offers
   container, object`. It is answered before an id is drawn, so no app is left kept with nothing
   made, as 23f191e8 was; `deploy` in `code/products/control/src/api/api.res` describes the binding
   first.
4. **A function is deployed into what the binding holds**, provisional, chosen by the advisor on
   2026-10-26, vr5lw: where the binding offers `container` the control asks its capacity item as
   today and the function runs in it, dg903; where it does not, as on Cloudflare, it asks no item
   and sends no `into`, and driver(cloudflare) names the Worker by the app's 8 hex already,
   `cloudflare/function/src/function.res`. The deployment row gains the kind chosen, written before
   the driver is called, so forget and retire read whether an app ran from it rather than from
   `capacity != 0`, which a function on Cloudflare never sets, `api.res`'s `forget` and `retire`.
   Describe is unchanged: it passes on the driver's answer, `running` with the Worker's address,
   `workers` and `isolate`.
5. **A function app is reached through its organization's gateway**, decided by the author on
   2026-10-26: the gateway of vr5lw, one per organization, bound to `{organization}.{apps}`,
   answering `/v{n}/{scope}/...`, an app mounted by a row of the scope table. It runs on a binding
   the organization chooses, its traffic leaves through it, and the platform recommends placing it
   on Cloudflare, where a Cloudflare app's path from the gateway is inline inside Cloudflare, the
   workspace's deferred item inline-data-path. Until it lands the control's `/v1/<id>/` keeps
   answering `beyond_host` for a function on a binding reached by its origin,
   `code/products/control/src/gateway.res`. Meanwhile, provisional, chosen by the advisor on
   2026-10-26, a check reaches such a function at the address describe answers, a test and never
   the path published.
6. **instance stays a named kind no driver offers yet**, provisional, chosen by the advisor on
   2026-10-26: it is matched as the others are, and a release declaring it alone is refused by
   point 3 until dg903 and nrs5v give it, as a Durable Object class its bundle names.
7. **A release with no kinds is read by its form**, provisional, chosen by the advisor on
   2026-10-26, the form being a fact of the code too: modules and component as function, image as
   container. Every release kept is modules, so each reads as function and, on a machine binding
   offering `container`, asks the same capacity item and sends the same deploy as today; every app
   deployed so far moves nothing. A deployment row with no kind reads as having run where its
   capacity is not 0, as now. A describe with no `kinds` reads as function and container, the one
   driver that answered before vbg0u.
8. **Where each change lands**, provisional, chosen by the advisor on 2026-10-26: monoflake/platform
   alone carries code, the deployments and releases contracts, the control's `deploying.res`,
   `api.res` and `state.res`, the deploy tool, and this RFC; vr5lw gains the compute kinds' enum by
   name. monoflake/driver changes no code, both drivers answering `kinds` and driver(cloudflare)
   naming a function's Worker by its app already; its RFC nrs5v gains a line that a function there
   is deployed with no `into`. monoflake/cloud takes the pin move and the run sheet deploying hello
   as a function. The gateway's placement is the work point 5 opens, proposed apart first.
