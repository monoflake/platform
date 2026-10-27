---
name: 'Control Routes and App Ingress'
title: 'A control answers its interfaces, artifacts, relay and objects alone; a gateway Worker of its own, optional, carries a declared domain or a mount to an app; and an app has no way in from outside until it declares one'
status: accepted
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

A control answers today, in one Worker, its interfaces, its artifacts, the relay, objects, and
every organization's gateway, `/v{n}/{scope}/...`, RFC vr5lw. An app on a machine is reached from
outside only through that branch: `Gateway.passed` finds the binding the app's deployment runs on
and sends the request to the binding's address through the control's reach, with `Host`
`{app}.b{binding}`. So a control's name answers apps' paths, and a control deployed as an app on
another platform, a container on one of its bindings, hangs on the gateway branch of the control
beneath it. vr5lw also gives every organization a gateway always. What does a control answer, what
carries a name to an app, and how is an app reached from outside?

## Decision

Decided by the author on 2026-10-27, relayed by the advisor; what is marked provisional was chosen by
the advisor on 2026-10-27 for the author to confirm. It revises vr5lw where vr5lw has a gateway in
every control and in every organization; the rest of vr5lw stands.

**A control answers four kinds of path and nothing else.**

| Path                          | Method | What                                                                                                                                                                                                     |
| ----------------------------- | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/{interface}/{operation}`    | `POST` | a call, RFCs fhg6w and 6x8su: `organizations.open`; `bindings.open` and `bindings.bind`; `reaches.open`; `releases.put`, `releases.deploy`, `releases.describe`, `releases.forget` and `releases.retire` |
| `/artifacts/{hash}`           | `GET`  | an artifact, its hash 64 hex digits                                                                                                                                                                      |
| `/relay/{address}/{port}/...` | any    | the relay to a binding's address, an address of the platform's private range                                                                                                                             |
| `/object/{name}`              | any    | an object, as the relay serves it                                                                                                                                                                        |

- **A call carries its version in its body**, as RFC 6x8su has it, so no `/v{n}` is on a control's
  path.
- **The gateway's branch leaves the control's Worker.** Any path outside the table answers 404, and
  no app is reached through a control.
- **A control is reached at a name of its own**, which the deployment chooses; how the hosted
  platform names its two is monoflake/cloud's RFC 7dbmi.

**The gateway is a product of its own, `code/products/gateway`, a Worker apart from the control**,
provisional. The control's gateway code moves into it. It answers two forms:

- **a declared direct domain, by `Host`**: the request's host is looked up among the domains apps
  declare, and the request passed as `Gateway.passed` passes it today, through the same reach, to
  the address of the binding the app's deployment runs on, with `Host` `{app}.b{binding}`;
- **a mount, by `/v{n}/{scope}/...`**, as vr5lw's `scope` table has it, the rest as today.

- **It reads the control's state from the same database, bound to it as well, and never writes
  it.** The control alone writes its state.
- **What it answers at is a deployment's choice.** A name of its own for mounts may answer 404 until
  something is mounted.
- **It answers on names bound to it alone**, its generated address off, `workers_dev` false.

**A gateway is optional**: a platform may run this Worker or not. Without it, nothing answers from
outside but a control's own routes, and an app is reached only by another app binding it.
vr5lw's every organization holding a gateway always no longer holds; what a mount answers, and
the rules every answer of a gateway carries, stand as vr5lw has them.

**An app has no way in from outside by default, and gains one only by declaring it.** Its ingress
is one or more of:

- **a direct domain**: an apex, a subdomain or a wildcard, carried to the app by the gateway;
- **a mount on a gateway**, under a scope;
- **the binding itself**: the name `{app}.b{binding}`, as `Gateway.host` builds it, given only when
  declared, provisional.

Several may be declared at once. **An app declares its ingress in its release, beside the bindings
it declares**, generated into `model/contracts.json` as every record is, provisional; vr5lw's
warning of an app nothing reaches reads it. An app declaring none is reached only by another app
binding it, RFC 49qyg, and is warned of as vr5lw has it. **A declared domain is bound to the
gateway's Worker by hand for now**: a driver binding the domains its apps declare by itself is
work of its own.
