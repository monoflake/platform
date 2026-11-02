---
name: 'The Component Test Bench'
title: "A component is held to its samples by a test bench that plays its deployer: deployed through a driver's own deploy on a driver apart, trusting the run's root, given its key as a deployment carries it"
status: accepted
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

RFC p8e8k has the runner reach an implementation through its contracts alone, as the party above it
would, with no back door for a test, and sign `as` by a chain it makes fresh each run, "the
implementation started trusting that root". It does not say who starts a component, where, or how
the root and the component's own key reach it. The runner today takes a running `--base` and starts
nothing, `code/tools/runner/src/main.res`, so the issuer's samples, `tests/components/issuer/`,
cannot run.

## Decision

Decided by the author on 2026-10-24: **the test bench plays the deployer.**

- The bench deploys a component through a driver's `deployments.deploy`, the same start path the
  platform uses, never a start made for a test.
- As conform already does, `model/graph/tools.res`, the bench starts a second driver on the test
  machine from the driver's binary, with bindings of its own, deploys the component there, runs the
  samples, and removes everything the run made.
- Rejected: starting the component directly in workerd or node, a second way to start a component
  that drifts from the deployer's and a back door at start that RFC p8e8k forbids at a call; and
  deploying onto the live driver for each run.
- The samples then also hold the start path, so certificates, secrets and workerd's configuration
  are tested as they ship. The bench is long-lived: it is how every component is held to its
  samples, in development and in CI, never where the platform keeps data.

What follows from it:

- **The bench makes the chain first**, then deploys the component with what a deployment carries:
  the root it trusts, and its own certificate and key as the deployer would hand them.
- **The bench is the issuer's authority in a run.** RFC 7xpd3 has the control certify the issuer's
  key with the organization's key; in a run the bench plays that party, which is RFC p8e8k's "the
  runner is its authority", so the runner's chain gains the role `issuer`.
- **The authority certifies the issuer's working keys**, as `docs/signed.md` and RFC 7xpd3 have it;
  RFC b8f35's line that the intermediate does is the earlier word, and the later decision holds.

**The bench stands in for the footing, for now**, decided by the author on 2026-10-24, a
safe-bootstrapping stand-in: something temporary hired in while the real mechanism is not there,
then replaced by it. The bench answers the footing's contract for reading a bundle alone, as RFC
n8jq5 declares it in the model. It makes each case's bundle from the case's grants and signs it with
the run's chain, which gains the role `bundle`. Rejected: handing the bundle to the issuer with its
deployment, which would change the issuer's edge in the design; and holding the issuer until the
real footing exists. The stand-in is tracked so it cannot become permanent, a scaffold of the bench
retired when the footing and its samples land, the workspace's deferred item `bench-footing`; then
the issuer's run reads the real footing and the stand-in is deleted.

### Ledger

Choices made provisionally while the thread runs, read by the author at its end.

- **C36, how soon a new bundle is seen, stays open as a number**, provisional, chosen by the advisor
  on 2026-10-24. In a run, a case expecting a new bundle's effect uses `within`, which the runner
  retries, RFC p8e8k, with the bound the case writes.
- **`capabilities` are answered in the order the bundle lists the grants**, provisional, chosen by
  the advisor on 2026-10-24, so a positional match is deterministic.
