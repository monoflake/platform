---
name: 'Compat and Versions'
title: 'Everything the platform writes carries one integer version, raised only by a breaking change; every reader accepts a range; and one library, compat, says how, on a frozen core that never changes and so needs no version'
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

Taking a consensus algorithm out of the layers as a library, RFC b8f35, raised what every library
shared by many parts must face: they are deployed one by one, so old and new run side by side, and
what one writes another must read. Worked out with the author on 2026-10-15, as part of rebuilding
the platform's libraries with its apps rather than inheriting them.

The shape the discussion has reached so far, to be decided once it is diffed against what exists:

**A version is an integer, raised only by a breaking change.** A field added is no break and raises
nothing, because two rules hold for every reader: **a field it does not know is passed over**, and
**a field that is missing has a meaning written down**, the old behavior as a rule. A breaking
version compiled but not yet deployed or released, still only local, may be taken back, since
nothing anywhere has seen it: a version is spent only when it is released.

**What is written carries one version; what reads accepts a range.**

| Version    | What it says                                         | Carried by                           |
| ---------- | ---------------------------------------------------- | ------------------------------------ |
| on disk    | the format a piece of data was written in            | the data itself, as long as it lasts |
| of a build | which versions a library or binary reads, and writes | the build, replaced as it deploys    |

- A reader declares the range it reads, `[lowest, highest]`; its highest is what it could write.
- **What is written lags what is read by one step**, so nothing is written that a reader still
  running cannot read: a new build reads `[n, n+1]` and still writes `n`; once every reader running
  reads `n+1`, writing moves to it -- the lowest of every running reader's highest, which the
  platform computes rather than anyone deciding; once nothing of `n` is left, a build drops it and
  reads `[n+1, n+1]`. Between two parties talking, the range is one version most of the time and
  two only while a change rolls out.
- **On disk, the lowest is set by the oldest data still kept**, never by the code: data lasts, a cold
  archive perhaps for years, so a reader keeps its old versions until what was written in them is
  moved -- rewritten when it is next read, or by a sweep -- and the platform counts what is left in
  each version to know when.
- **What a version cannot say, a set of features does.** A field added under the same version is
  not known to be supported by asking its number; where a new feature must be supported by both
  sides and not merely ignored, each declares the features it has, and what both have is used, as
  the vocabulary of capabilities compares a set, RFC 49qyg.
- **A library whose output must agree between parts -- where a container goes, how content is cut,
  how a key is derived -- breaks with any change to its output**, since two parts computing it
  differently would lose data between them; it raises its version for every such change and writes
  that version into what it produces.

**`compat`, a library, is the one way all of this is done**, so every part and library versions
alike: the stamp, the range, the features, choosing what is written, and the reason a version is
refused. **Its core is frozen and so needs no version**: a version is one non-negative integer, the
first thing read, compared by its value -- nothing more, and never changed, as the version field
at the front of a network packet has not. **The rest of `compat` is versioned by that core** like
any other library, and so can change. An unsigned 32-bit integer, or a number in a text format, is
more versions than a format will break in its life.

**The deployer keeps every running build's range and computes what is written**, since it alone
knows what is deployed where: before it replaces a part, the new build must read what its neighbors
write now, and they must read what it will write; and the version written moves to the lowest of
every running reader's highest once a replacement lands.

Open, for the discussion that follows:

- How the data kept in each version on disk is counted, and by which part, so that a reader knows
  when it may drop an old one. [C13]
