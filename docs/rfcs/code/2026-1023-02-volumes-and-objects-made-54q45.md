---
name: 'Volumes and Objects Made'
title: 'The fourth thread: a volume and an object made on a machine, the object kind held to its samples there'
status: accepted
supersedes: []
blocked-by: [ehm48]
commits: []
references: []
---

## Question

A machine's driver gives a volume and an object besides compute, `model/ground/drivers.res`, and
neither is made yet: an item of either reaches `todo!("4elqc")`, so `conform` finds the object
kind's cases waiting. What does a machine make of a volume and of an object, and how is the object
kind held to its samples on a machine.

## Decision

Decided by the author on 2026-10-23.

- **A volume and an object stay two kinds**, as the model has them: an object reached through its
  contract, which the Cloudflare driver gives as well, a volume by none, mounted rather than
  called. On a machine both stand on one thing, **a btrfs subvolume under a quota group's limit**,
  so the volume is the machine's bottom and an object's bucket is made of it.
- **The rest of RFC 4elqc's third item is built as it proposes**, provisionally: a volume a subvolume
  of its item's size, a bucket a subvolume holding the object store, each assigned to its
  binding's quota group, and an item unmade when a list drops it past its grace, removing what it
  made.
- **The platform still keeps no data**, `docs/method.md`: what a test machine holds may be wiped.
- **The samples reach more**: the runner builds the samples' fixtures, sets up a case's `given` and
  makes a `send` on the machine, RFC p8e8k, so `conform` runs what it skipped.

| Step | What                                                               | Where    | Done when                                                     |
| ---- | ------------------------------------------------------------------ | -------- | ------------------------------------------------------------- |
| 1    | The volume as a block, and volume and object items made and unmade | driver   | `conform` finds the object kind's cases passing on a machine  |
| 2    | The runner's fixtures, `given` and sends on the machine            | platform | `conform` runs the deployments cases it skipped, none failing |
