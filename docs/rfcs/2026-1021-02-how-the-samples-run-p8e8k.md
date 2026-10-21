---
name: 'How the Samples Run'
title: 'What the runner does with every key a sample may hold, so an implementation is held to the samples through its contracts alone'
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

RFC vr5lw has every implementation held to the samples in `tests/`, and
`model/checks/written/cases.res` holds each sample to the contracts. What a program running them
does is written nowhere: how an answer is matched, what a placeholder makes, how `given`, a fixture,
`as`, `lose` and the properties are brought about. The runner, `code/tools/runner`, is the first
such program.

## Decided

Decided by the author on 2026-10-21, as the agent proposed them that night.

- **The runner reaches an implementation through its contracts alone.** Whatever a case needs set
  up, it sets up as the party above the implementation would: a kind's `given` through the same
  driver's `management`, as a control does, with a binding's token; a product's through its
  organization's control; a component's by being its authority and its issuer, signing the bundle
  and the capabilities. No back door is opened for a test, so what passes is the path a caller
  takes.
- **What a sample names is checked, and nothing else.** An answer is read as every reader reads it:
  a field the sample does not write is passed over, whether the contract knows it or not, and only a
  field the sample writes and the answer lacks or holds otherwise fails. A field that must be
  absent is written `$absent`. A failure is matched by its `failure` and its `reason`; its
  `message` is for a person and never matched.
- **`$any` is present, with any value.**
- **`$bytes` are the same bytes every run, in every language, and compress as little as anything
  real**: the BLAKE3 of the case's description, the step's index and the value's path, joined by
  `/`, read out in its extendable output to the length asked. Zeros would dedupe and compress, and
  hide what a store does with real data.
- **`within` is retried by the runner**, after 100 ms, doubling to at most 2 s between tries, until
  the step answers as expected or the time is past; a failure names the last answer and how many
  tries there were. No sample says how often.
- **`wait` moves a clock where the implementation lets the runner hold one, and sleeps where it
  does not**; a case waiting long is marked slow, and a run may leave slow cases out.
- **A fixture is built from its source, beside its `fixture.json`**: a module bundle's JavaScript, a
  component's source, an image's Dockerfile, in `tests/fixtures/<name>/`, made by a tool
  deterministically, its hash computed. The runner serves it over HTTP itself, so `served` and
  `padded` are the runner's doing: the bytes as built, bytes that do not match their hash, a refusal
  to serve, bytes past a bound.
- **`as` is signed by a chain the runner makes for the run**: a root, an intermediate, an authority,
  the organization and the component, each as the platform makes them, its keys made fresh each
  run, and the implementation started trusting that root.
- **`$signed` is verified, never only decoded**: to the runner's own root, which made the chain the
  implementation signed under, and its claims then matched as any value is. A signed record that
  does not verify fails its step.
- **A case is run in both forms, CBOR first**: both are the platform's, CBOR its own, and a codec
  that answers the two unlike is found by the same sample.
- **`lose`, the properties and `$frames` are run through what the implementation offers for them**:
  a fault it lets the runner cause -- a copy's process stopped, a partition -- for `lose`; a history
  of every call and answer kept by the runner, checked after the run, for the properties --
  `single_instance`, never two holders of a lease at once; `read_after_write`, every read after a
  write answered seeing it; and SQLite run inside the runner for `$frames`.
- **A bound a driver declares is asked of the driver through its contract**, [D8], never written in
  the runner's configuration.

## What the first runner leaves for later

Each is a case the runner reports as skipped, naming this RFC, never as passed: a fixture, which
needs its source and its builder; `lose`, the properties and `$frames`, which need what the
implementation offers for them; `given` past a kind's, and a driver's declared bounds, which wait on
the binding's token and D8. Until a driver answers its bounds, the runner reads them from its
configuration, and says so.
