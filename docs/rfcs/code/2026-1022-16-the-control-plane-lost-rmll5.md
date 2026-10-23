---
name: 'The Control Plane Lost'
title: 'The second thread: hello served while the control plane on its machine is stopped'
status: accepted
supersedes: []
blocked-by: [n0o4l]
commits: []
references: []
---

## Question

The scope's first promise is that the data plane keeps serving while the control plane is lost,
`docs/scope.md`. RFC n0o4l built the entry inside `driver-machine`, so stopping the driver stops
every request with it, where RFC vr5lw has the entry a listener its driver deploys beside the
deployments. How is the promise held on a machine, and proved by running rather than on paper.

## Decision

Decided by the author on 2026-10-23.

- **On a machine the control plane is the driver's management and deployments, and what calls
  them**, the `deploy` tool among it; the data plane is the entry, the deployments' containers and
  the tunnel, each running on with the driver stopped.
- **The entry is a process of its own**, a unit beside the driver's, finding a deployment's address
  from containerd, which is ground and no part of the control plane; the tunnel reaches it. The
  driver no longer serves the entry.
- **The promise is a command that can fail**: `mise run lose <target>` stops the driver, asks hello
  through the entry and the tunnel the whole time, finds `deploy` refused cleanly, starts the
  driver again and finds everything as it was, and reports.
- **A machine restarted while its driver is stopped is not taken here**: its containers are started
  again by the driver as it starts, the deployer's work, RFC wnqvu, left to a later thread.

| Step | What                                             | Where                  | Done when                                                           |
| ---- | ------------------------------------------------ | ---------------------- | ------------------------------------------------------------------- |
| 1    | `lose`, run once as things stand                 | platform               | its report shows hello failing while the driver is stopped          |
| 2    | The entry its own unit, the tunnel pointed at it | driver, machine, cloud | `lose` finds hello answering throughout, and `conform` still passes |
