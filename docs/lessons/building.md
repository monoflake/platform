# Building

Facts on where and how code is built, each with its source; see `docs/lessons.md`.

## Building code, read 2026-10-18

**`workerd` is no hardened sandbox.** "`workerd` on its own does not contain suitable
defense-in-depth against the possibility of implementation bugs"; "When using `workerd` to run
possibly-malicious code, you must run it inside an appropriate secure sandbox, such as a virtual
machine." Apache-2.0. Asked of V8 on a machine, RFC vr5lw. Source:
https://github.com/cloudflare/workerd

**A GitHub Actions workflow is started by the API, with no push.** `workflow_dispatch` takes a ref
and at most 10 inputs, its workflow file on the default branch; `repository_dispatch` takes an event
type and a payload, and is reported to start only the default branch's workflow, to be confirmed.
Asked of building for a target, RFC vr5lw. Sources:
https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow and
https://github.community/t/how-to-trigger-repository-dispatch-event-for-non-default-branch/14470

**GitHub Actions is free on standard runners for a public repository, and counts minutes for a
private one against its owner.** GitHub Free includes 2,000 minutes a month, Pro and Team 3,000;
past them a spending limit of 0 by default stops runs. "Minutes usage is charged to the repository
owner, not the person who triggered the workflow runs." Source:
https://docs.github.com/en/actions/concepts/billing-and-usage

**GitHub Actions keeps an artifact 90 days unless set otherwise**: 1 to 90 days for a public
repository, 1 to 400 for a private or internal one, a change reaching only what is made after it.
Source:
https://docs.github.com/en/organizations/managing-organization-settings/configuring-the-retention-period-for-github-actions-artifacts-and-logs-in-your-organization

**Cloudflare's Workers Builds builds a connected repository, and its deploy command may be
changed.** Free: 3,000 build minutes a month, 1 build at a time; paid: 6,000, then $0.005 a minute,
6 at a time; 20 minutes a build, 2 vCPU, 8 GB of memory, 20 GB of disk. "Your deploy command will
default to `npx wrangler deploy` but you may customize this command"; `npx wrangler versions upload`
makes a version and deploys nothing. A build is started by `POST
/accounts/{account_id}/builds/triggers/{trigger_uuid}/builds`, a branch optional, with a user-scoped
token holding Workers CI Write -- an account-scoped one is refused -- or by a deploy hook, 10 a
minute a Worker and 100 an account. Sources:
https://developers.cloudflare.com/workers/ci-cd/builds/limits-and-pricing/,
https://developers.cloudflare.com/workers/ci-cd/builds/configuration/ and
https://developers.cloudflare.com/workers/ci-cd/builds/api-reference

**A Worker can be rolled back to any of its last 100 versions**, raised from 10 in September 2025,
unless a binding it names is gone or a Durable Object class changed between them. Source:
https://developers.cloudflare.com/workers/versions-and-deployments/rollbacks/

**A Worker is at most 3 MB on the free plan and 10 MB on the paid, and its global scope runs within
a second.** The size is counted compressed; the startup limit was raised from 400 ms to 1 second in
October 2025, on both plans. Some older pages show 64 MiB and 400 ms, and are stale. Asked of what
bounds code on a target, RFC vr5lw. Sources: https://developers.cloudflare.com/workers/platform/limits
and https://developers.cloudflare.com/changelog/2025-10-10-increased-startup-time/

**A Worker's WebCrypto signs and verifies Ed25519**, by the name `Ed25519` under the Secure Curves
API, or the older `NODE-ED25519`, which takes no raw private key. Asked of the signed record of RFC
b8f35. Source: https://developers.cloudflare.com/workers/runtime-apis/web-crypto/
