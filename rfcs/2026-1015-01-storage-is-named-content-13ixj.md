---
name: 'Storage Is Named Content'
title: 'An app stores files by name in datasets an owner holds, the names pointing at content addressed by a hash keyed to that owner, and reads them back by name or by an immutable link'
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

The platform is to give an app three stable things -- functions to run in, a database and a
storage -- and keep everything beneath them its own, so that what serves them can be replaced, split
or moved while the app keeps running and never knows. Worked out with the author on 2026-10-15,
top down from what an app needs, before any implementation and apart from every earlier design of
the platform's storage; how it lands, and how it differs from what exists, is left for after the
functions are settled too. The question here is the storage's shape as an app sees it.

It is smaller than an object store on purpose: a restricted set an app can rely on without thinking
about anything but its own logic.

This is layer 0, the platform's face, as RFC vuanj numbers the layers.

The shape the discussion has reached so far, to be decided once it is diffed against what exists:

**An owner holds datasets, and a dataset holds files by path.**

```
owner (one scope, its own unique salt)
  dataset
    {path}/.../{path}/{file}
  dataset
    ...
```

- **A dataset is one level only and never nested.** It is the scope of a policy: its tier of
  durability, its kind, a quota, who may bind it, and deletion of the whole. A part that needs
  another policy is another dataset.
- **A dataset's policy is chosen by its kind, never set flat**: what a kind lacks cannot be set.
  `content`, the default, is cut and deduplicated, and compressed and sealed unless set otherwise,
  RFC b8f35. `opaque` is kept as given, each file exactly 16 MiB -- neither cut, compressed nor
  sealed -- for what is sealed already above, RFC 94y0d. The tier, the quota and who may bind it are
  every kind's.
- **Durability is a tier, never a number.** A dataset names how much its data matters; the
  platform maps each tier to how many stores may fail with nothing lost, and to a layout that bears
  it -- whole copies, or pieces with parity -- chosen by size and by how many stores the scope has.
  A count written into a dataset could never change; a mapping can, and changing one is when data
  moves to its new layout. **A user's data is kept once unless its owner asks for more**: the
  lowest tier is one copy and is the default, and redundancy is a tier chosen.
- **One or many apps may bind a dataset.** An app holds no state; it knows a dataset and the paths
  it writes in it, nothing beneath.
- **A path is a key split by `/`**, so a directory is only a prefix and a file may sit at the top,
  `(dataset)/{file}`. The app names files freely.

**What an app can do:**

| On      | Operation                                                                              |
| ------- | -------------------------------------------------------------------------------------- |
| dataset | `create` with its policy, `head`, `list`, `delete` (only while empty)                  |
| file    | `put(dataset, path, content) -> {hash, size}`, `get`, `head`, `list(prefix)`, `delete` |
| link    | `link(dataset, path) -> url`, the content the path names at this moment                |

- **A name points at content; content never changes.** Writing a path again points it at new
  content, and a write may be conditional on the hash it last saw, so two writers never silently
  overwrite each other. A directory is never renamed.
- **Creating a path and replacing one are separate rights.** A write to a path that exists is a
  replacement, which can lose what it pointed at as a deletion can; one allowed to create alone is
  refused there, so a dataset can be written only forward -- a backup, an audit log -- by a function
  that, taken over, could add and never erase.
- **Content is addressed by its hash, keyed to the owner** -- BLAKE3 keyed by the owner's salt,
  RFC b8f35. The same content stored twice within one
  owner is stored once, across datasets and apps alike; across owners the same content has a
  different hash, so an address cannot be computed by anyone outside the owner, and nothing is
  shared between owners.
- **A link is the content's, not the name's**: a URL carrying the hash, through the platform's
  gateway -- its prefix the gateway's, which delivers the rest to the storage unread, so the rest is
  the storage's own to shape -- answered with a strong `ETag`, `immutable` and a year's cache,
  public or private. Private is decided by who asks, never by a parameter on the URL, so the address
  stays one. Content made public cannot be recalled from caches the platform does not hold.
- **When names disagree, the most permissive wins.** The same content named in two datasets, one
  public and one private, has one link, and it is public, since what one name published is already
  out; `head` on the private side says so.
- **Content held for datasets with different policies is held to the strictest of them**, the
  highest tier any of them asks.

**Beneath the app, and invisible to it, is the storage's own metadata**: an owner's datasets, each
dataset's paths and the hash each points at, the content's own metadata, and the access each grants.
Writing a path updates every directory above it up to `/` in the same step, so a directory's size and
count are read, never computed, when it is listed.

Open, for the discussion that follows:

- Whether that metadata is held per owner or per dataset. Deduplication and the count of names
  pointing at each hash are an owner's, which argues for per owner. [C9]
- The capability's name, since it is not an object store. [A9]
- Whether one content named in a `content` and an `opaque` dataset is kept once, and how. [C8]
