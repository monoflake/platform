---
name: 'Declared Privileges'
title: "A deployment declares the system privileges it needs, none by default, and only the operator's may declare any"
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

A `container`, RFC vr5lw, is an ordinary process with a volume of its own and nothing of the host.
Some services the operator runs need more of a machine: a router across the fleet needs the
host's network, its capabilities and host ports. Decided by the author on 2026-10-27: **a
deployment declares the system-level classes it needs, such as `network` or `cpu`, and declaring
none means no privilege at all, an ordinary container**. Only the operator's deployments may
declare a class; an organization's never does.

Also decided by the author the same day:

- **Images reach every node the same way**: CI builds an image and uploads it to the operator's
  object storage, and a node downloads it through Cloudflare. A node inside a censored border
  cannot pull from a public registry, and this path has been tested from inside many times.
- **A privileged service's secrets come through the platform's own mechanism**, never a host
  secret store handed in.

Which classes exist beyond `network`, and how a class is approved for one deployment, are open.

## Options

- **The class list beyond `network`**: `cpu`, as a cpuset or a realtime priority, is the one named
  so far, and its contents are open; any further class waits for a decision of its own.
- **How a class is approved per deployment**: by the operator's credential alone, since only the
  operator may deploy one, or by a record the operator makes beforehand naming the deployment and
  its classes, so a stolen deploy credential cannot add a class on its own.

## Evidence

- The first privileged service is a router with lines across a censored border. It needs the
  host's network namespace, `CAP_NET_ADMIN`, `CAP_NET_BIND_SERVICE`, `/dev/net/tun` and a few host
  ports, so the class is not hypothetical. It also keeps an nft table of its own, an allowlist of
  the other nodes' addresses, which `CAP_NET_ADMIN` already covers.
- Host networking and those capabilities are root-equivalent on the machine, so a class open to an
  organization would hand it the host; refusing every class to an organization keeps RFC vr5lw's
  container what it is for them.
- On 2026-10-27 every machine runs containerd, but only two run the machine driver; the nodes the
  first privileged service runs on get the driver before its first deployment.
- A node inside the border found a Cloudflare tunnel path slow on 2026-10-08. That is a different
  path from an object download, so the first deployment times an image fetch on such a node.

### Ledger

Choices made provisionally while the thread runs, read by the author at its end.

- **Each class is a fixed, documented set of OCI and runtime settings**, provisional, chosen by the
  advisor on 2026-10-27, never free-form fields a deployment fills in.
- **`network` is the host's network namespace, `CAP_NET_ADMIN`, `CAP_NET_BIND_SERVICE`,
  `/dev/net/tun`, and the host ports the deployment declares**, provisional, chosen by the advisor
  on 2026-10-27. The driver opens those ports in the host firewall at deployment and closes them on
  removal. It is never a privileged container.
- **An organization's deployment that declares any class is refused**, provisional, chosen by the
  advisor on 2026-10-27, at the control before anything is asked of a driver.
- **A further class comes only by a later decision**, provisional, chosen by the advisor on
  2026-10-27.
