---
name: 'Root and Backing'
title: 'Beneath the parts, layer -2 holds a root nothing can start without and a backing per scope -- where its bytes are kept and with which keys -- which the blob reads downward and no capability carries'
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

RFC vuanj built the products from five parts at layer -1 and left for layer -2 where they stand,
control among them. Starting layer -2 with the author on 2026-10-15, the first question is its
bottom: what nothing can start without, and where a scope's bytes go, which a user may now choose
by bringing an object store of their own.

The shape the discussion has reached so far, to be decided once it is diffed against what exists:

**Control is not a part.** What it held is taken apart by what each piece is, and each goes to the
layer it belongs to. **The name is kept, reserved for the platform's control plane as a whole** --
its entry -- whose extent is not yet discussed.

**Each product keeps its own configuration, per scope, in a tablet of its own**, as it keeps
everything else: the storage its datasets and their policies, the database its directory of
names, and functions their apps, each app's deployed versions by code hash, its functions'
declarations, its triggers, its env and its bindings. **Nothing holds every scope's configuration
at once.** The issuer, signing a call's capabilities in a scope, reads that scope's function tablet
with a standing capability the intermediate key signs, covering those tablets in every scope for
reading; a part checks it against the root's public key as it checks any other, so nothing turns
back up to the issuer.

**A scope is two halves, and they live at different layers.**

| Half     | What it holds                                                                                         | Layer         |
| -------- | ----------------------------------------------------------------------------------------------------- | ------------- |
| logical  | Its id, whether it exists, the datasets and databases it holds                                        | -1, `scope`   |
| physical | The stores its bytes go to -- the platform's, or a user's own -- with their secrets, tags and weights | -2, `backing` |

The blob reads a scope's backing, a dependency that points down. **A capability never carries
configuration**: it proves what its holder may do, and a store's address and secret are not that;
carried in one, a change would not reach the capabilities still alive.

**Layer -2 has four parts, and a library is none of them:**

- **`root`**: what nothing can start without, and nothing else. It changes rarely and by an
  operator.
- **`backing`**: each scope's physical half, changed while the platform runs, as when a user adds a
  store of their own. **It stands on layer -3's primitives directly, never on a tablet**, since a
  tablet stands on the blob and the blob on it. Who may change a scope's backing is decided by a
  capability, checked against the root's public key alone, so the backing never reaches up to the
  issuer. **It holds a scope's stores and nothing else**: each store's address, its secret, the
  tags a dataset's policy chooses stores by, never a store by name, its weight, and its **grade**:
  how far it can be trusted and how soon what is written to it lasts; and, while the
  stores change, the generation before, read from until what it held has moved. A scope's salt and
  key are not kept here or anywhere: they are derived from the root's masters and the scope's id.
  The tier a dataset asks for is the dataset's, carried down with each write, and how a tier is laid
  out is the blob's.
- **`extent`**: what a blob's content is made of. **Below the blob, content is cut into blocks of
  about one size**, a large file split and small ones packed together, so stores fill evenly, a
  layout with parity has something to split, and moving data moves blocks alike. The extent keeps
  which blocks each content hash is made of, with each one's offset and length -- which cannot be
  computed, since what was packed with what depends on when it came, and which deduplication reads
  first. **Where a block is, it computes** from the block's hash and the scope's stores, and keeps
  only the exceptions: a block passed to the next store while one was down, until the repair moves
  it back. It stands on layer -3 directly, as the backing does, since a tablet stands on the blob
  and the blob on it.
- **`host`**: a place that runs sandboxes. A host says which sandboxes it offers -- a V8 isolate,
  WebAssembly -- and what they can reach, in the vocabulary of capabilities RFC 49qyg declares needs
  in: `network` and whatever comes after. The executor hands each call to a host that offers what it
  declared. **A sandbox is the single isolated unit a host runs a call in**; a host holds many.

**A library is no layer.** Shared code is not a dependency: each part that needs a library runs its
own copy of it, so it is no node in the graph of layers and may be used at any of them. **A library
depends on no part**: what it needs, its caller hands it. A thing is a library only when each caller
may have an instance of its own; one whose state two callers must see the same is a part. Libraries
are marked `*`.

- **`quorum*`**: the one way anything is kept by more than one copy, **a library, so that every
  group of copies is its own** and none fails with another: given its copies -- an odd number that
  vote and any number that only receive -- and each one's grade, it keeps a log: who writes now, at
  which generation, and which entries a majority of the voters have confirmed. What counts as a
  copy's confirming is derived from its store's grade and never written by hand -- a cloud's object
  store lasts at once, a machine at home only once written through. A writer of an older generation
  can confirm nothing, so two never write at once. A user's tablet runs one with its scope; the
  anchor, the backings and the extent run theirs with none, kept by the platform for all. **A group
  keeps its log on its copies' own stores and never in the blob**, which stands on several of them.
  A pointer to a tablet's newest state is no part of its own: its group is that pointer. Its copies
  talk to each other, so it carries a protocol version and reads the one before, RFC wnqvu.
- **The root stands at the bottom**, below the anchor: it depends on nothing, and everything needs
  it, the anchor's own group the grades of the platform's stores among them.

**The backing is per scope; what finds it is not, and goes one layer down.** A scope at this layer
still has storage of its own, so something must say where each scope's is. That is the **`anchor`**,
at layer -3, standing on a vendor's primitive directly with nothing of the platform's beneath it:
a scope's id and a reference to where its backing is, a row each. **A scope exists while its row
does**, and is gone when it is removed. The anchor is the platform's only global state, and it
holds nothing else: every product's configuration, every dataset and database, every app's
declaration stays in its scope.

A user appears this low only as configuration: a store given to their own scope. The parts' logic
does not change for it.

**The root is no running service, so it has no uptime to lose.** What it holds is of two kinds:

| Held                                        | Used by                                    | Where                   |
| ------------------------------------------- | ------------------------------------------ | ----------------------- |
| the root private key                        | an operator, certifying the issuer's keys  | offline, never deployed |
| the root public key                         | every part, verifying a capability's chain | deployed to every part  |
| the salt master                             | the one part that derives a scope's salt   | deployed there alone    |
| the encryption master                       | the one part that derives a scope's key    | deployed there alone    |
| the platform's own stores and their secrets | the backing                                | deployed there alone    |

- **A capability is signed through three levels**: the root private key, offline, certifies an
  intermediate key for a long time; the intermediate, online, certifies the issuer's working keys
  for a short one and rotates them unattended; a working key signs capabilities. A part holds the
  root's public key alone and checks the chain, so a leaked working key is worth a short while, and
  the root private key is used rarely.
- **The salt master never rotates**: a new one would change every scope's salt and so every hash,
  and it never leaves the platform, which keeps how it could leak to the platform itself broken.
- **The encryption master carries a version.** A rotation writes new data under the new version and
  leaves the old under its own; retiring an old version re-encrypts what still uses it.
- **The root private key is held by the platform's administrator.** Lost, a new pair is made and
  every node deployed again with its public key; no data is lost.
- **The two masters are kept as a key group for recovery alone**: each split into three shares,
  any two of which restore it and so make the third again, held in three places. A part starts from
  its deployed secrets and never waits for a share; the shares are used only when a master is lost
  with what it was deployed to, since a master lost is every scope's data lost.

Open, for the discussion that follows:

- Where the source of what is deployed from the root is kept, and how it reaches each part.
- Where the three shares of each master are held.
- What the control plane is and how far it reaches, the name reserved for it.
- Which vendor primitive the anchor stands on, and which the backing does, and how a scope's salt
  and key are kept in it.
- How many copies the platform's own quorums keep, and of which grades.
- The grades: how many, and what each means for confirming.
- The tiers: how many, their names, and what each maps to.
- How big a block is, and how small a file is before it is packed.
- How stores are added to a scope, which is to come down from what the layers above need.
