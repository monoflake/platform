---
name: 'What Releases Leave Open'
title: "What releasing still asks: the release delay a runtime's scheduled run keeps, what starts that run, and where a machine's binary cache is kept"
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

Left open by RFC m7rkq.

Proposed by the agent on 2026-10-21, not yet confirmed:

- An upstream release is taken once it is past the workspace's release delay, as `pins` took
  workerd's, so the scheduled run in `monoflake/runtime` keeps the same rule.

Deferred by the author on 2026-10-22:

- GitHub disables a scheduled workflow after 60 days without a commit, so a run started by
  `repository_dispatch` from this repository's CI may be the main trigger and the schedule a
  fallback.
- A binary cache of the machine's NixOS, so a machine downloads its system rather than building it,
  cannot be a release asset; where it is kept, an object store with Nix's signing key, is open. The
  hosted fleet's own answer is monoflake/cloud's RFC u9fxz.
