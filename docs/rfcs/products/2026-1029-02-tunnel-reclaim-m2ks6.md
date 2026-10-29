---
name: 'Tunnel Reclaim'
title: 'What a control does with the tunnel and binding it made when the route to the host fails, and how a control replacing another in one account keeps its addresses from meeting the routes the first one left'
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

A control binds a host by opening a binding, drawing it an address, making a tunnel named by the
binding's id and routing the address to that tunnel, RFC rxmd9. Two things went wrong on
2026-10-29 when a test control was replaced by a new one in the same account. When the route
failed, what should the control do with the tunnel and the binding it had already made? And how
should a new control's addresses keep clear of routes an earlier control left in the account?

## Options

For the failed route:

- **Reclaim in the same call**: on a route refused, the control deletes the tunnel it made and
  closes the binding before answering, so a failed bind leaves nothing. Needs the control to close
  a binding, which it cannot yet.
- **Retry by the binding**: keep the binding and the tunnel, answer the failure, and let the host's
  next bind with the same token try the route again, the made tunnel found by its name. Leaves both
  standing where the host never retries.

For the collision:

- **Read before drawing**: the control lists the account's routes and draws no address one holds.
- **Clear at install**: installing a control removes every route and tunnel in the account that
  no record of its own names, as the reset's sweep would.
- **A range per control**: each control's addresses come from a range of its own, drawn at install,
  so two controls never share one.

## Evidence

- **A failed route leaves its tunnel and its binding behind.** The new control opened a binding
  and made its tunnel, then the vendor refused the route, the address being routed already. The
  bind failed with that refusal, but the tunnel stayed in the account with no route and no
  connection, and the binding stayed open with no host, holding the address. Neither is reclaimed:
  the tunnel was deleted by hand, and the binding stays until a control can close bindings.
- **A new control's first address is an earlier control's.** Each control draws addresses from
  the same private range starting at its first, so the new control's first binding was given the
  address the old control's binding held. The old binding's route was still live in the account,
  and the vendor's routes are the account's, not the control's, so the new route was refused.
  Deleting the old tunnel and its route by hand let the next bind through.
- **The design expects one control per account**, so the collision appears only when a control is
  replaced, as at a reset; a platform's reset replaces every one.
