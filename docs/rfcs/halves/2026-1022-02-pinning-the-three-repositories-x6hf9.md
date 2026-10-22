---
name: 'Pinning the Three Repositories'
title: 'Until the repositories release, one built on another checks it out in CI at a commit that update moves'
status: landed
supersedes: []
blocked-by: [7ykg6]
commits: [workspace@78471756, monoflake/driver@cf0a35a0]
references: []
---

## Question

Left open by RFC 7ykg6.

The driver is built on this repository's crates and contracts, reached by path as `../platform`,
and cloud on both. At home the sibling is the checkout beside it; in CI nothing is beside it, and
nothing of this repository is published to take instead. How does CI build a repository on
another before either releases, and what does one build take.

## Decision

Decided by the author on 2026-10-22.

- **Nothing is published to a registry yet**: this repository's crates and packages stay `0.0.0`,
  `Blocks.unpublished`, and a repository built on another reaches it by path, at home and in CI
  alike.
- **CI checks the sibling out at a commit**, written in the workflow with the branch it follows
  beside it, `ref: <commit> # monoflake/platform@main`, so one commit of the driver builds the same
  on every run.
- **`update` moves the commit to the branch's head**, the workspace's actions mover a repository
  takes with `actions = true`, with no day's wait since the branch is the author's own, the move
  reviewed and pushed by hand as every update is. At home the sibling is whatever is checked out.
- **How the repositories pin one another's releases once they publish, and what CI checks the
  whole across them, is RFC q4pfb.**
