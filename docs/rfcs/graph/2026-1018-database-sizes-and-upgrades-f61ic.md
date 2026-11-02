---
name: 'Database Sizes and Upgrades'
title: "What three in, three out still asks: the database's two sizes, a machine's own upgrades, and a container checkpointed whole to disk"
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

Left open by RFC vr5lw.

Open, for the discussion that follows:

- The database's sizes, a small one and a large one, and what each is made of. [C23]
- A machine's own upgrades, staggered and run by its driver, and what carries a workload across them.
  [C32]
- A container checkpointed whole to disk by CRIU, a cold pause that frees its memory and outlives a
  reboot, and whether it carries a container across a machine's upgrade. [C39]
