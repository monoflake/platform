---
name: 'Releases Across the Repositories'
title: "How the repositories pin one another's releases once they publish, and what CI checks the whole across them"
status: draft
supersedes: []
blocked-by: [x6hf9]
commits: []
references: []
---

## Question

Left open by RFC x6hf9.

Until this repository publishes, the driver and cloud check it out at a commit. Once its crates and
packages are taken from a registry, how is each versioned, how does a repository built on another
pin its releases in place of a commit, and what CI checks the whole the three make, cloud's whole
check holding a private repository.

## Options

Raised with the author on 2026-10-22, none taken yet.

- **Every released block versioned as the driver is**, RFC 8c0rg: the major the author's alone,
  the minor raised when an interface it serves is, the patch on every other release and reset by
  the minor, each counted from the last release by the workspace's `scripts/release` rather than
  by each repository.
- **A library's public API is what the minor follows**, either the contract or wit version it
  declares it implements or what a tool finds changed in its exports, `cargo-semver-checks` and
  its TypeScript equivalent.
- **A version shown by a build is the released one**, given at build time, not the manifest's.
- **Past `1.0` a minor stays compatible**: either a raised interface is served beside the old one,
  or a raise that drops it raises the major. Left until the first block nears `1.0`.
