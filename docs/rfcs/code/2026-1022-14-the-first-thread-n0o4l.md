---
name: 'The First Thread'
title: 'The first thread: one request from outside reaching a Worker on a test machine and its answer returning'
status: accepted
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

Nothing the platform describes has served a request. What is the thinnest thread through every
layer, `docs/method.md`, "Held on paper, found by running", and in what steps is it built.

## Decision

Decided by the author on 2026-10-22.

- **The app is a hello Worker in two homes**: written with Hono for the runtime both drivers give,
  deployed to Cloudflare by `wrangler deploy` as it is and to a test machine through the platform
  unchanged.
- **What is not built**: the authority, the directory, a bundle's signature, the database, the
  storage, the tablet and the extent. Each edge the thread crosses that the model marks by hand on
  day one is filled by hand behind its contract: a key made once, a credential signed by a command,
  the driver's own token.
- **A machine takes a build two ways**: a release locked in its `manifest.lock`, once the author
  opens releases, and a local override, a path the module runs in its place when a test machine's
  configuration sets it, as Cargo's `path` stands in for a version. A production machine never sets
  it.
- **The provisional choices**, each changed by what running shows: the request reaches the machine
  through a Cloudflare Tunnel, which ends TLS in place of the machine's certificate RFC vr5lw asks;
  a machine's list is kept in one file and a deployment named by its id, the rest of RFC 4elqc left
  `todo!`; the entry is a listener in `driver-machine`, choosing a deployment by the request's host.

The steps, in order, each one worker's and done when the author can try it:

| Step | What                                                                                         | Where                  | Done when                                                         |
| ---- | -------------------------------------------------------------------------------------------- | ---------------------- | ----------------------------------------------------------------- |
| 1    | The local loop: `mise run dev <host>` builds, copies, restarts and checks, `--watch` on save | driver, machine, cloud | a change saved on the Mac serves on the machine in under a minute |
| 2    | A list kept across a restart, the least of RFC 4elqc                                         | driver                 | a deployment survives the driver's restart                        |
| 3    | The entry, a request for a host handed to its deployment                                     | driver                 | `curl` on the machine reaches hello                               |
| 4    | The way in from outside, the tunnel and a name                                               | cloud, machine         | hello opens on a phone                                            |
| 5    | `deploy`, a Worker bundle wrangler builds sent as a list                                     | platform               | one command deploys hello                                         |
| 6    | The samples sent to what is deployed                                                         | platform               | one command reports the machine meets its contracts               |

The threads after it, each its own RFC when it starts: the control plane stopped while hello serves;
the driver replaced while hello serves; an object kept.
