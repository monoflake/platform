---
name: "A Component's Own Id"
title: "A component deployed into a scope is that scope's resource, a record of kind `component` whose id the deployer draws, and a deployment of it names that id"
status: accepted
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

RFC b8f35 has an id of 8 hex digits name one resource of a scope and carry its type, whatever its
kind. monoflake/driver's RFC nrs5v, decided by the author on 2026-10-24, names what a driver holds
for the platform by that resource's id, bare, so a deployment's Worker is named by its deployment's
id. `deployment-runs`, `model/contracts/kinds/deployments.res`, identifies an app by its id but a
component by its name alone, so a component's deployment has no id to be named by.

## Decision

Decided on 2026-10-24, following RFC b8f35 and the author's rule that every resource in an
organization carries the organization-unique id, whatever its kind.

**A component deployed into a scope is that scope's resource**, a record of kind `component` in the
organization's half, `model/contracts/records/control.res`, and `deployment-runs`' `component` case
gains its `id` beside its name. The deployer draws the id, the control above the binding, as it
draws every id in the scope; a driver never does, being beneath the scope and minting only ids for
its own parts.

### Ledger

Choices made provisionally while the thread runs, read by the author at its end.

- **The id names a record of kind `component`**, provisional, chosen by the advisor on 2026-10-24, as
  it follows from RFC b8f35: an id with no record kind behind it breaks an id naming one resource and
  carrying its type, and the model could no longer tell what the id names. One record per component
  deployed into the scope; its fields are the component's name as the model names it, and nothing
  more until a sample needs more; its writer is the control, the deployer, which draws its id as it
  first deploys that component into the scope; its id is never given to anything else, as every id
  is. Its name is unique among the kind's rows, as `scope` keeps its own; it declares no history
  or deletion, as no kind of its half does.
- **`id` is required, and the interfaces using it are raised**, provisional, chosen by the advisor
  on 2026-10-24: `deployments` one version, `management` 2 to 3. Every caller and both drivers are
  ours and nothing is released; a required field now is a mechanical change, and an optional one
  now a known break later, plus a field whose absence means "not given yet", which RFC b8f35 rules
  out. `management` 3 also holds RFC vbg0u's fields. `configuration` 1 to 2 and `releases` 1 to 2
  are raised with them, accepted by the advisor on 2026-10-24, the same decision's mechanical result:
  the new kind changes `configuration`'s record and change, `releases` names `deployment-runs`, and
  the model keeps no version over a changed type.
- **Until the control deploys components, the bench draws a component's id**, provisional, chosen by
  the advisor on 2026-10-24, as it plays the deployer for everything else, RFC 9bq0y; so a driver
  always has an id to name a component's Worker by.
- **Platform-given values go on `deployment-deploy`, never on `deployment-runs`**, provisional,
  chosen by the advisor on 2026-10-24, as the integrator placed them. `deployment-runs` is echoed back
  in describe, adopted and releases, so a key placed there would leave in answers; deploy-only input
  is where a secret belongs. Each value is typed as what it is: a certificate is public, RFC b8f35's
  "no signed record holds a secret", and so is the root's public key, and marking them secret would
  mask what is not secret and teach that the type means nothing. So `handed`, key 12, is a list of a
  union, its case naming the value and carrying its own type: `root` bytes, `key` secret,
  `certificate` bytes, `signing_key` secret. The names stay fixed by the contract, a case handed twice
  answers `invalid`, which `deploy` declares, the driver binds each under its `MONOFLAKE_`
  name, and the driver keeps refusing the prefix on a deployment's own secrets.
- **`reaching`, key 13, a list of `deployment-runs` on the same binding**, provisional, chosen by the
  advisor on 2026-10-24 as the integrator proposed it: driver(machine) opens the bridge to those
  alone, and a target not on the binding answers `invalid`. It stays out of `deployment-network`,
  which says what kind of destination a deployment leaves for, not which deployments it reaches.
  driver(cloudflare) reads both fields and answers `reaching` as `beyond_host` while its half is
  deferred, the workspace's `inline-data-path`.
- **The deploy field is `handed`, what the platform hands a deployment, its union
  `deployment-handed`**, a small matter, provisional, chosen by the advisor on 2026-10-24. `given`
  collided with the samples' `given`, the setup a case asks for, and the bench reads both side by
  side; docs/naming.md allows one word two meanings only where they are never read together. The
  samples' `given` keeps its name, and a key saying the stand-in does not answer belongs to it, not
  to the deploy field.
- **Every handed value is lowercase hex text, a secret too**, provisional, chosen by the advisor on
  2026-10-24, in every driver, and the issuer reads hex.
- **A deployment reaches its targets through the machine's local entry, by name**, a small matter,
  provisional, chosen by the advisor on 2026-10-24, replacing its earlier "a stable address derived
  from the deployment id". `MONOFLAKE_REACHING` maps each target's id, in 8 lowercase hex digits,
  to one origin, the local entry with the target's deployment name as the host, as JSON text
  declared where the driver spells it, RFC y6lg7. That never changes when the target is replaced,
  since the entry routes by host to whichever container serves, as the clock's tick is delivered,
  RFC p6fg3. The fence lets a reacher reach the entry's port alone, and only a reacher with a
  non-empty `reaching`, by `(reacher address, entry address, entry port)` elements in the machine's
  nftables, monoflake/driver's RFC p95sv; the entry then allows a request only when its source
  deployment and the named target are a pair in `reaching`, and refuses the rest. Every deployment
  keeps RFC vr5lw's replacement with no gap, targets included. The address changing under a
  reacher was a symptom of naming targets by address; the entry already holds the name-to-container
  map, so naming by host removes the clash. workerd opens the private network and the fence
  narrows it.
- **A reacher resolves its targets' names by its own `/etc/hosts`**, a small matter, provisional,
  chosen by the advisor on 2026-10-24. A container declaring `reaching` is given one line per name
  in its own `reaching`, each mapping to the entry's address, and nothing for any other name; a
  container with no `reaching` is given none. A name a container may not reach so does not resolve
  there, a second layer beside the entry's check, which stays the gate. The lines are written as
  the container is made, since a changed `reaching` comes only with a replacement. The entry's
  address and port come from one place each, so the hosts line, the fence's element and the entry's
  own `--subnet` never drift apart. Rejected: a service binding in workerd, which changes the
  binding's shape and covers the function kind alone, and a resolver on the machine, a DNS service
  monoflake/machine would have to run.
- **driver(cloudflare) refuses a deployment's own secret named with the `MONOFLAKE_` prefix as
  `malformed`**, provisional, chosen by the advisor on 2026-10-24, as driver(machine) does.
- **Stop-before-start is left only where it is still needed**, a small matter, provisional, chosen
  by the advisor on 2026-10-24, and as built nothing needs it: with targets reached by name through
  the entry, no deployment needs a namespace of its own deployment's or a gap, so every deployment,
  reachers and targets alike, keeps RFC vr5lw's replacement with no gap.
- **With `reaching`, the fence drops every private destination but the targets**, a small matter,
  provisional, chosen by the advisor on 2026-10-24: RFC 1918, ULA and link-local alike. Without
  `reaching`, private stays closed, as today. The rules are run on Linux at the bench's rehearsal
  on the test machine before the fence counts as done; a rule tested as text alone is not tested.
- **The deployer's `version` covers what it hands**, a small matter, provisional, chosen by the
  advisor on 2026-10-24, as the bench counts the footing into it. The driver keeps "same version,
  nothing done", so an instance key renewed each day, RFC b8f35, is a new version and deploys.
- **A container made before this change is rebuilt by the driver where its form changed**, a small
  matter, provisional, chosen by the advisor on 2026-10-24, one at a time, keeping the old until the
  new one serves where it can, RFC vr5lw, so what a machine runs stays up through the switch. A
  restart goes on past one failure and reports each. As built, an app's container keeps its form,
  so none is rebuilt; a component's container labelled by its name carries no id and is left
  running as it is. Rejected: deleting and deploying again every deployment on a machine, which
  would stop what serves there.
- **The driver rewrites the whole `reaching` set at start and periodically**, a small matter,
  provisional, chosen by the advisor on 2026-10-24, since a fence reverted or a reboot leaves it
  empty or stale and tells the driver nothing. A periodic rewrite inside the machine is no timer
  across Cloudflare and a machine, so RFC rxmd9 does not bear on it.
- **A container's request to the host keeps its source address, observed before it counts**, a
  small matter, provisional, chosen by the advisor on 2026-10-24: the entry's pair check is done
  only once the bench's rehearsal on the test machine has observed it, a check of the run sheet.
- **The entry keeps its public path through a containerd outage**, a small matter, provisional,
  chosen by the advisor on 2026-10-24: when containerd cannot be listed, a request from outside the
  subnet to an app is served at its last known address for at most 60 seconds. That path never
  checked a source pair, being the public way in, and refusing it would cut every public app at
  each restart of containerd. The pair check and a component's path stay closed through the same
  outage, the two judged apart. A stale address cannot pass to another container inside the
  window, since no container is made while containerd is down and the first listing that succeeds
  replaces what was kept.
- **The entry looks for a request's source in the target's binding alone**, a small matter,
  provisional, chosen by the advisor on 2026-10-24: a source missing from that binding's list is
  refused, and a deploy already refuses a `reaching` target of another binding, so a container of
  one binding never reaches another's deployment.
- **`reaching`'s sample is a file of its own, `tests/kinds/deployments/reaching.json`**, a small
  matter, provisional, chosen by the advisor on 2026-10-25. A sample file named for a feature is run
  by the drivers that offer that feature and by no others: each driver's in-process sample test
  lists its files by name and lists this one only where it offers `reaching`, conform reads the
  whole directory since driver(machine) offers it, and a third driver decides by the same rule.
  driver(cloudflare)'s `beyond_host` is held by its own tests until `inline-data-path` replaces them
  with the file. The sample expects the entry's own 403 carried back whole; the fence's checks stay
  in a machine's rehearsal.
- **The entry reads `X-Forwarded-Host` only on its proxy paths**, a small matter, provisional,
  chosen by the advisor on 2026-10-25: cloudflared on loopback and the gateway's path through the
  tunnel. A request from the containers' subnet is named by its `Host` alone, any
  `X-Forwarded-Host` or request target's authority on it ignored, since a container is nobody's
  proxy and a gate letting a caller pick the name it is judged by does not fail closed. So
  `reaching.json` holds the allowed half alone; the refusal is held by driver(machine)'s entry
  tests, by `Host` and by an ignored `X-Forwarded-Host`, and by a machine's rehearsal, curl from a
  reacher's namespace naming a target it does not reach and getting the 403 whole.
- **A container's forwarding headers carry nothing through**, a small matter, provisional, chosen
  by the advisor on 2026-10-25: from the containers' subnet the entry drops `X-Forwarded-For`,
  `Forwarded`, `X-Forwarded-Proto`, `X-Real-IP` and any other forwarding header, the chain starting
  at the container's source alone; proxy paths keep theirs. The earlier entries' "the sample expects
  the entry's own 403" gave way to the allowed half alone, above; the fence's two drivers and
  conform's bridge are monoflake/driver's RFC p95sv's Ledger of 2026-10-25.
- **No header describing forwarding or the client carries through from the subnet**, a small
  matter, provisional, chosen by the advisor on 2026-10-25, completing the entry above: `Via`,
  `Forwarded`, `CDN-Loop`, every `X-Forwarded-*` and `X-Original-Forwarded-*`, every `CF-*`, and
  `True-Client-IP`, `X-Real-IP`, `X-Client-IP`, `X-Cluster-Client-IP`, `Client-IP` and
  `Fastly-Client-IP`, each matched with `_` read as `-`, since some servers fold the two. A request
  from the subnet carrying `Host` more than once is answered 400, never judged by one of them.
