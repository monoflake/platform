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

- **A dataset is one level only and never nested.** It is the scope of a policy: its placement, its
  kind, a quota, who may bind it, a description, and deletion of the whole. A part that needs
  another policy is another dataset.
- **A dataset's policy is chosen by its kind, never set flat**: what a kind lacks cannot be set.
  `content`, the default, is cut and deduplicated, and compressed and sealed unless set otherwise,
  RFC b8f35. `opaque` is passed through raw, each file at most 16 MiB -- never cut, compressed or
  sealed, since whether it is either already is not the platform's to know -- as what the external
  platform seals is, RFC 94y0d. The placement, the quota, who may bind it and the description are
  every kind's.
- **A dataset's placement says what its data needs, and each store says what it is**, declared by
  whoever binds it as it is bound, RFC b8f35; the platform places each container only on stores
  that meet every need. **Every attribute is ordered**, so content named in several datasets is held
  to the highest of each that any of them asks.

  | Attribute    | Asks of a store                            | Levels, lowest first                                                                | A dataset's default |
  | ------------ | ------------------------------------------ | ----------------------------------------------------------------------------------- | ------------------- |
  | availability | how surely it can be reached               | `opportunistic`, `best_effort`, `stable`, `recoverable`, `redundant`, `multiregion` | `best_effort`       |
  | durability   | how surely what it holds lasts             | `ephemeral`, `persistent`, `redundant`, `replicated`, `multizone`, `multiregion`    | `persistent`        |
  | custody      | whether the organization alone controls it | `false`, `true`                                                                     | `false`             |

  A store's availability is `opportunistic` while it lasts and may be gone at any moment without
  warning, as a machine given free; `best_effort` with no redundancy and no steady environment, as a
  machine at home; `stable` in a steady environment, not necessarily redundant; `recoverable` with
  steady network and power, restarting itself after a crash, though it may be cut off a while;
  `redundant` failing over without going offline; `multiregion` redundant across places that share
  no data center, power or network, and no one disaster.

  A store's durability is `ephemeral` when what it holds is lost as it restarts, as memory or a
  temporary disk; `persistent` surviving a restart, on one disk; `redundant` surviving a disk lost,
  mirrored or with parity within one machine; `replicated` surviving a machine lost, held on several
  at one site; `multizone` surviving a data center lost, across the zones of one region;
  `multiregion` surviving a region lost.

  **A level is stored as its code**: availability's and durability's from 1, the lowest, to 6,
  custody's 0 for `false` and 1 for `true`, compared as integers; 0 is never an ordered level's
  code. It is written out as its name only where text must carry it: `best_effort` in JSON and an
  API, `best-effort` in a derive context, and in code as its language names things.

- **Spread is how many copies, and what they must be distinct in.** `copies` is the least kept;
  `distinct` maps a domain -- `node`, `site`, `account`, `zone`, `region` -- to how many of the
  copies at least lie in different ones of it, none more than `copies`. With `distinct` empty,
  `copies` is 1, since copies free to share a node withstand nothing and only spend. `copies: 3`
  with `distinct: {node: 2, account: 2}` is three copies, two at least on different nodes and two at
  least in different accounts. Each store declares the node, site, account, zone and region it
  stands in as it is bound. **A user's data is kept once unless its owner asks for more**: one copy
  is the default. Whether copies are laid out whole or as shards with parity, and whether the owner
  sees which, is to be decided. [C21]
- **A placement is checked against the scope's stores before it is saved**, and refused if they
  cannot meet it; a store is removed only while every dataset's placement still holds without it.
  What follows when a store is lost without warning, or reaches an end its owner did not choose, is
  to be decided. [C20]
- **A dataset not sealed and placed on a store outside its organization's custody is in a warning**,
  kept as a field and never refused: never dismissed, shown on the dataset's own page and as it is
  created, and nowhere else.
- **A description is free text**, empty unless written, and changed at any time.
- **One or many apps may bind a dataset.** An app holds no state; it knows a dataset and the paths
  it writes in it, nothing beneath.
- **A path is a key split by `/`**, so a directory is only a prefix and a file may sit at the top,
  `(dataset)/{file}`. The app names files freely.

**What an app can do:**

| On      | Operation                                                                              |
| ------- | -------------------------------------------------------------------------------------- |
| dataset | `create` with its policy, `head`, `list`, `delete` (only while empty): configuration   |
| file    | `put(dataset, path, content) -> {hash, size}`, `get`, `head`, `list(prefix)`, `delete` |
| link    | `link(dataset, path) -> url`, the content the path names at this moment                |

- **A dataset is configuration, a file is data.** Creating or deleting a dataset changes the
  organization's configuration, through its organization's own control, which an app may call as
  any client does, RFC v7v3w; a file's operations are the data plane's.
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
  highest of each attribute any of them asks.

**Beneath the app, and invisible to it, is the storage's own metadata**: an owner's datasets, each
dataset's paths and the hash each points at, the content's own metadata, and the access each grants.
Writing a path updates every directory above it up to `/` in the same step, so a directory's size and
count are read, never computed, when it is listed.

Open, for the discussion that follows:

- Whether that metadata is held per owner or per dataset. Deduplication and the count of names
  pointing at each hash are an owner's, which argues for per owner. [C9]
- The capability's name, since it is not an object store. [A9]
- Whether one content named in a `content` and an `opaque` dataset is kept once, and how. [C8]
- What follows when a store is lost without warning, or reaches an end its owner did not choose.
  [C20]
- Whether copies are laid out whole or as shards with parity, and whether the owner sees which.
  [C21]
