---
name: 'The Protocols Are in TLA+'
title: What order and which states are safe is a TLA+ specification checked by TLC
status: decided
supersedes: []
references: []
---

## Question

A day's defects passed the type checker and every unit test, each one found by a reviewer or on a
machine: a version check no rollout order could pass, a roll building from a commit that moved an
owner backward, an expired pointer failing an update, a power cut booting the older generation. No
layer of the model could ask whether an order of steps is safe.

## Options

- Stateright: its gain is sharing code with the model, and these protocols run across ReScript, Rust
  and Nix, so it was not taken.
- TLA+ with TLC, taken.

## Decision

The author's, on 2026-11-01, taking TLA+ as the industry's standard for this, with no pilot first.

- **TLA+ answers what order and which states are safe.** The ReScript model answers what the
  standard is and whether it is met, Nix what a machine is, and the implementation is the fact of
  what runs.
- **Each fact has one home.** A specification's constants come from the model rather than being
  written twice.
- **A specification and the code are tied together, or it decays.** TLC's traces become tests of the
  code's decisions; a specification with no such tie is a document.
- **The tools come through mise**, as each layer pins only the layer beneath it, docs/toolchain/versions.md.
