---
name: 'Gateways an Organization Makes'
title: "Where an organization's gateways run, how many it makes, and how a name and a mount reach each"
status: accepted
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

An organization's gateway, RFC vr5lw, is the way an app is reached under the organization's
platform name. Where does a gateway run, how many does an organization have, what is it on each
kind of binding, how does a mount reach what it mounts, and what becomes of the control's own
`/v1/<id>/`.

## Options

What the decision below leaves open, each with the integrator's recommendation, proposed on
2026-10-26 and open until settled:

- **Which gateway holds `{organization}.{apps}`**, where an organization has several: one gateway
  holds it, chosen by the organization; each gateway is given a label of its own under the
  organization's; or none holds it until the organization chooses one. Recommended: none until
  chosen, then the one chosen, so the platform name never answers from a gateway the organization
  did not name, and a second gateway is reached at a name of the organization's own.
- **How a mount names its gateway**: a row of the `scope` table naming the gateway's id beside the
  scope and the app, vr5lw, so one app may be mounted under several gateways, each row its own;
  the table's key becoming the gateway and the scope.
- **What a gateway is on each kind of binding**: a function on every one, one bundle of modules
  declaring `"kinds": ["function"]`, matched as any app is, RFC emgxf. On Cloudflare
  driver(cloudflare) deploys it as a Worker of the customer's account; on a machine it runs for
  workerd in the binding's container of capacity, dg903, behind the entry holding its names and
  the certificate vr5lw gives a machine serving a gateway. Its mounts are handed to it by the
  control, as configuration it reads or by a deploy again at each mount changed, to be chosen.
  A mount reaches what it mounts by the shortest path the two share:
  - on one Cloudflare binding, a service binding from the gateway's Worker to the app's, named by
    the app's 8 hex, which driver(cloudflare) makes, a mount changed being the gateway's bindings
    changed in its settings with its code unchanged, the Cloudflare half of the workspace's
    deferred item inline-data-path;
  - on one machine binding, its loopback, that item's machine half;
  - on another binding, the public network to the app's own address with a capability of the
    organization's, vr5lw, the data leaving the gateway's binding, so an app is best placed with
    its gateway.
- **The control's `/v1/<id>/` stays a stand-in for the operator's checks** until a gateway
  serves, answering `beyond_host` for a function on a binding reached by its origin meanwhile,
  `code/products/control/src/gateway.res`; then it is retired, as the `app-` scaffold was at
  8yl4b, and the control answers its API alone.
- **The platform's name reaches a gateway on Cloudflare by Cloudflare for SaaS in the customer's
  account**, the `{apps}` zone being the platform's and never the customer's: the customer's
  account holds a zone of its own, made the SaaS zone, with the gateway's Worker its fallback
  origin on a route `*/*` and `{organization}.{apps}` one of its custom hostnames, and the `{apps}`
  zone points that name by a CNAME at the customer's CNAME target. Proxied, that CNAME is
  orange-to-orange, the `{apps}` zone's settings applied first; DNS only, the gateway's rules are
  its own alone, as vr5lw has them. Validation and the certificate are the SaaS zone's, by a record
  the `{apps}` zone writes, so the records pointing a name stay the platform half's, vr5lw. It asks
  a zone of each customer placing the gateway holding the platform name on Cloudflare, and is to
  be tried before it is relied on.

## Evidence

Each fact on Cloudflare below is quoted with its source in `docs/lessons/cloudflare.md`, "A name
reaching a Worker of another account".

- A Worker Custom Domain is made only on a zone its account owns, so a name the customer holds in
  their account reaches the gateway's Worker by a Custom Domain with nothing more, and
  `{organization}.{apps}`, the `{apps}` zone being the platform's, cannot.
- A CNAME across accounts fails as 1014 unless its target uses Cloudflare for SaaS, so
  `{organization}.{apps}` cannot point at the gateway's Worker address, nor at a hostname of the
  customer's zone, unless that zone uses Cloudflare for SaaS.
- Cloudflare for SaaS serves a hostname of another's on a zone on any plan, 100 hostnames
  included, a Worker serving them as the fallback origin on a route `*/*`, each hostname validated
  and given its certificate by a record its holder writes.
- Orange-to-orange is that CNAME proxied, the pointing zone's settings applied first, and only
  between zones of different accounts.
- Workers for Platforms keeps its Workers in the account its namespace is in, so it gives a name of
  the `{apps}` zone no way into another account, and one gateway in the customer's account needs
  none of it.

## Decision

Decided by the author on 2026-10-26. vr5lw's "every organization has one, part of what the
platform gives it" is amended to this; vr5lw is landed and stays as written, so this RFC
supersedes none of it whole.

1. **An app is reached only in the ways vr5lw names**: a name bound to it, a mount under a
   gateway, or another app's binding. By default an app has no public name of its own, so it is
   reached through a gateway. Where its organization has no gateway and no name is bound to it,
   the app is unreachable by design: nothing tries to reach it, and the platform says so plainly,
   the warning of vr5lw and v7v3w. An address a driver's describe answers, as a Worker's, is a
   path for a check and never one published, RFC emgxf.
2. **A gateway is one an organization makes**, none, one or several, each placed on a binding of
   its choosing, its traffic leaving through that binding. The platform recommends making one on
   Cloudflare, on the customer's own account bound by BYOC, so traffic goes out through
   Cloudflare.
