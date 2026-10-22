---
name: 'What the Host Leaves Open'
title: "What the host chose where RFCs vr5lw, vuanj and b8f35 are silent: how the executor names a deployment at a host, the address described on every call, a deployment making or failed, an instance's key on a path, what a host offers, who chooses among hosts, and the paths in the bundle"
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

Left open by RFCs vr5lw, vuanj and b8f35, and by RFC ot812 for the paths in the bundle. What is
built is `code/substrate/host`, `Host.Handed.call`: a call of an export of what a deployment runs,
described by the host's driver through `deployments` and posted to the address it reports, held to
`tests/kinds/deployments/` by a fake driver answering them. What it does not decide waits on
`%todo("C44")` where it would; the rest is proposed here and not built.

Open, for the discussion that follows:

- **How the executor names a deployment at a host.** RFC vr5lw fixes how a deployment is called,
  `POST {address}/{export}` and `POST {address}/{key}/{export}`, in its app's own WIT, and the model
  has the executor reach the host by `wit`; neither says where the host is reached nor how a call
  names the deployment. Proposed: the host serves `POST /{runs}/{export}` and
  `POST /{runs}/{key}/{export}`, `{runs}` being `app/{id}` or `component/{name}`, the body and the
  answer carried unread, so it declares no interface of the platform's subset; it is served by
  `serve*` once its calls are signed, taking `serve*`, `codec*` and `capability*` then, as it takes
  `envelope*` now for the contract's types. The executor finds what runs a code by its bundle's
  compute section, the app whose `version` is the code's hash, and the hosts it was placed on.
  [C44]
- **The address is described on every call.** Built so: each call asks its driver `describe`, and
  a stopped deployment, which has no address, is answered `unavailable`, `stopped`, without a post.
  Proposed: the host keeps the last running address of each deployment and describes it again only
  where a post to it is refused or its bundle's generation moves, so a call costs one hop; the
  samples hold either. [C44]
- **A deployment still making, or failed.** The correct path hands it no call, since code is
  deployed before any call reaches it and a version takes calls once every host of its set holds
  it. Proposed: both answer `unavailable`, `making` a reason of its own and a failed one its
  driver's reason, so the executor goes on to another host of the set. [C44]
- **An instance's key on a path.** The samples' keys are one letter, and a key holding anything past
  RFC 3986's unreserved characters waits. Proposed: a key is percent-encoded as one path segment,
  and an empty one refused as malformed before any driver is asked. [C44]
- **What a host offers, and how it reports it.** RFC b8f35 has a host say which sandboxes it offers
  and what they reach, in the vocabulary, and `?roster` has each host report itself; neither says
  from what. Proposed: its `sandbox` is some of what its driver's runtimes give, `workers` and
  `workerd` giving `v8` and `wasmtime` giving `webassembly`, an OCI runtime none while a container
  is open, C11; its `network` what its deployments may reach; its `instance` where its driver gives
  one; reported through `?roster` as its configuration is applied. Not built, as no sample holds an
  offer, RFC ot812's question of what a host offers past its sandbox. [C44]
- **Who chooses among hosts.** RFC kd7f9 gives `meets` to the executor and the placement, so the
  host chooses nothing and takes `vocabulary*` only to state its offer. Proposed: the executor
  keeps the hosts of the app's set whose offers meet the call's need, and of a pool takes the first
  in the order its placement compiled that answers. [C44]
- **The paths in the bundle**, RFC ot812's, which waited for the host. Proposed: `bundle-host` gains
  `paths`, from each caller's extension by its id to the paths from it, each the jumps it crosses
  in order by their extensions' ids and whether it crosses the public network, fewest jumps first
  and then one off the public network first, as RFC vr5lw orders them; no jump is within a host;
  `extensions*` computes them. The lender's own record of a loan stays RFC 87lwb's. [C44]
