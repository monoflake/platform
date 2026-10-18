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

**Each product reads its own configuration from its organization's bundle, in the footing, never
from a tablet**, RFC v7v3w: the storage its datasets and their policies, the database its directory
of names, and functions their apps, each app's deployed versions by code hash, its functions'
declarations, its triggers, its env and its bindings. A tablet holds data alone. **Nothing in an organization's half holds
another's configuration**: the platform's half holds every configuration's truth, and each
organization a copy of its own, RFC v7v3w. The issuer runs in the scope's organization and signs
with that organization's own key, reading the scope's grants and allowance in the issuer's own
format, RFC vuanj -- never a product's tables -- so nothing turns back up to the platform's half.

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
  store of their own. **It is kept in the scope's footing, never in a tablet**, since a tablet
  stands on the blob and the blob on it. Who may change a scope's backing is decided by a
  capability, checked against the root's public key alone, so the backing never reaches up to the
  issuer. **It holds a scope's stores and nothing else**: each store's address, its secret, its
  weight, and what it declares as it is bound: its availability, durability and custody, and the
  node, site, account, zone and region it stands in, RFC 13ixj; never a store by name; and, while
  the stores change, the generation before, read from until what it held has moved. A scope's salt
  and key are not kept here or anywhere: they are derived from the root's masters and the scope's
  id. The placement a dataset asks for is the dataset's, carried down with each write, and how it is
  laid out is the blob's.
- **`extent`**: what a blob's content is made of. **Below the blob, content is cut into pieces,
  and pieces are packed into containers of about one size**, so stores fill evenly, a layout with
  parity has something to split, and moving data moves containers alike. The extent keeps which
  pieces each content hash is made of, and for each piece its container, offset and length and
  whether it is compressed -- which cannot be computed, since what was packed with what depends on
  when it came, and which deduplication reads first. **Where a container is, it computes** from the
  container's id and the scope's stores, and keeps only the exceptions: a container passed to the
  next store while one was down, until the repair moves it back. It is kept in the scope's
  footing, as the backing is, since a tablet stands on the blob and the blob on it. **An extent is a
  scope's**, since a container is sealed with the scope's key, so files of two scopes can never be
  packed into one, deduplication stays within an owner, and a scope is deleted whole. **The extent
  repairs**: knowing every
  container and every exception, it restores what a layout asks for after a store is lost or a
  container was passed on, and since containers are sealed and named by an unkeyed hash it needs
  neither the key nor the salt to do it. It must repair on its own while the control plane is lost,
  RFC vuanj. Packing is the extent's and sealing the blob's, which holds the scope's key in the
  organization's half, RFC v7v3w; a repack is the two together.
- **`host`**: a place that runs sandboxes. A host says which sandboxes it offers -- a V8 isolate,
  WebAssembly -- and what they can reach, in the vocabulary of capabilities RFC 49qyg declares needs
  in: `network` and whatever comes after. The executor hands each call to a host that offers what it
  declared. **A sandbox is the single isolated unit a host runs a call in**; a host holds many.
  A scope's hosts and stores are the resources bound to its organization, RFC v7v3w; on a machine,
  a host is what its one driver runs for that binding. **On Cloudflare each deployment is a Worker of its own**, made through the vendor's API by the
  account's driver as its configuration is applied, RFC vr5lw, since a Worker refuses code it is
  handed at run time, `lessons.md`; it is given only the bindings its capabilities allow, and its
  network only through the platform's own request interface. On a machine, a host is a process.

**A library is no layer.** Shared code is not a dependency: each part that needs a library runs its
own copy of it, so it is no node in the graph of layers and may be used at any of them. **A library
depends on no part**: what it needs, its caller hands it. A thing is a library only when each caller
may have an instance of its own; one whose state two callers must see the same is a part. Libraries
are marked `*`.

- **The root stands at the bottom**, below the anchor: it depends on nothing, and everything needs
  it.

**Every log is kept in a footing, and v0 has no quorum.** Each owner stands on one, RFC v7v3w -- an
organization's for its scope, the platform's for the anchor, D1 on the internal platform's own
account -- a database in SQLite's dialect that is ground, `scope.md`: trusted to be up and to keep
what it confirmed, its redundancy its own and never the platform's. **It coordinates its owner**: it
holds the backing, the extent's records, each tablet's log until a snapshot holds it, which journal
each placement writes, which writer holds what and at which generation, and the bundle. A writer of
an older generation is refused by the footing, so two never write at once. It holds no content, yet
the extent's records grow with the pieces a scope holds, about 200 bytes each, until the extent is
kept off it [B17]: its 10 GB holds some fifty million, about 50 TB of large files. A footing lost is
restored from its snapshot, RFC v7v3w.

**On Cloudflare a footing is D1 behind a footing Worker of the same account.** A Worker reaches it
by a service binding, a host on a machine over HTTPS with a capability, and nothing by D1's REST
API, which carries the Cloudflare API's limit, `lessons.md`. **The footing Worker groups commits**:
what reaches it within a moment is written as one batch, since a batch of 128 commits costs about
what one does, `lessons.md`. Every write it takes is a conditional statement -- a generation fenced
by `WHERE`, a writer taken over only past its lease, a count raised only while it is above zero --
so no transaction ever reads before it decides.

**A writer's lease is its writing.** Each entry of a tablet's log carries the time the footing gives
it, by the footing's own clock, so no host's clock is trusted. A writer holds its tablet while its
last entry is younger than the lease; idle, it renews nothing and writes no row, and writes on when
it next has something, as long as no one has taken the tablet over. Another writer takes it over
only past the lease, by one conditional statement that raises the generation where the last entry is
older than that; it then catches up, and the old writer's next entry is refused by the generation.
So an idle tablet costs its footing nothing, a taking over one row, and a write after a writer is
lost waits at most the lease. When a log is archived, its newest entry stays, since it dates the
lease.

**The backing is per scope; what finds it is not, and goes one layer down.** A scope at this layer
still has storage of its own, so something must say where each scope's is. That is the **`anchor`**,
at layer -3, kept in the platform's footing with nothing of the platform's beneath it:
a scope's id and a reference to where its backing is, a row each. **A scope's row is never
removed, so its id is never given again**, since a second scope under the same id would derive the
same salt and key. Its status says what is left of it:

| Status      | What it means                                                                   |
| ----------- | ------------------------------------------------------------------------------- |
| `active`    | it serves                                                                       |
| `suspended` | nothing it holds serves, and everything it holds is kept                        |
| `deleted`   | nothing it holds serves, and what it holds is erased; final, its id stays spent |

- **A suspended scope is deleted after seven days** unless it is made active again within them.
- **A scope is deleted the moment it is asked to be**: the status is written first, then a task
  erases what it held. An erasure cut short is no matter, since collection keeps only what a scope
  that is not deleted still holds, and drops what it finds of a deleted one.

The same holds for every id drawn where reusing it would derive what its first holder's did. The
anchor is the platform's only global state, and it holds nothing else: every product's
configuration, every dataset and database, every app's declaration stays in its scope.

**An id takes one of three forms**, stored as binary and written out as text only in a URL or
where it is shown, lowercase and at its full width, leading zeros kept:

| Written                          | Bits       | Made                         | For                                                   |
| -------------------------------- | ---------- | ---------------------------- | ----------------------------------------------------- |
| 5 characters of base36, `0-9a-z` | about 25.8 | drawn at random, and checked | a short link to a resource; none yet                  |
| 8 hex digits                     | 32         | drawn at random, and checked | an account, a scope, and each kind of resource in one |
| 64 hex digits                    | 256        | derived by BLAKE3            | content, at every layer                               |

- **An id drawn is checked as it is inserted**, by a conditional insert, and drawn again on a
  conflict. It is unique within its kind alone -- accounts among accounts, one kind of resource
  within its scope -- and the internal and external platforms check theirs apart, RFC 94y0d, so
  one id may name different things on each. Whether an organization keeps one scope id on both is
  decided when it arises. [C19]
- **An id derived is never checked and never shortened**: 256 bits are taken as never colliding,
  and a match is taken as the same content, so a shortened one would hand one owner another's.
- **Stored, it is an integer or bytes**: 8 hex digits as an integer, 64 as 32 bytes, base36 as an
  integer below 36^5. A derivation reads 8 hex digits as 4 bytes, big-endian, in the order they are
  written.

**A time is a count, never a text**, by the same rule as an id: stored and passed as an integer
of milliseconds since the Unix epoch, which is UTC by its definition. Where a text must carry one,
it is ISO 8601 in UTC, ending in `Z`; a zone other than UTC, and a pretty format, appear only where
a user is shown the time.

A user appears this low only as configuration: a store given to their own scope. The parts' logic
does not change for it.

**Whose a record is and where it is kept are two questions.** A record an owner's act brought
about -- a dataset or database opened in their scope, a schedule declared, a tablet placed -- is the
scope's: counted against its allowance and deleted with it, even when it is kept beneath the scope,
as its backing is. The scope itself -- its row in the anchor, its allowance -- is the platform's.

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
  the root private key is used rarely. **The intermediate key is rotated by the operator, offline,
  with the root private key**; what holds it online is the data plane's, since the issuer cannot
  sign past a working key's expiry without it, though it is needed once in a working key's life
  and never on a call.
- **The salt master never rotates**: a new one would change every scope's salt and so every hash,
  and it never leaves the platform, which keeps how it could leak to the platform itself broken.
- **The encryption master carries a version.** A rotation writes new data under the new version and
  leaves the old under its own; retiring an old version re-encrypts what still uses it.
- **A migration is the blob's own work**: to a new layout when a dataset's placement changes, to a
  new key when an old version is retired. The control plane starts it, as a caller, and the clock
  paces it; every piece stays readable throughout, and going slowly costs time, never correctness.
- **The root private key is held by the platform's administrator.** Lost, a new pair is made and
  every node deployed again with its public key; no data is lost.
- **The two masters are kept as a key group for recovery alone**: each split into three shares,
  any two of which restore it and so make the third again, held in three places. A part starts from
  its deployed secrets and never waits for a share; the shares are used only when a master is lost
  with what it was deployed to, since a master lost is every scope's data lost.
- **What the root holds is kept two ways.** The root private key and the masters' shares are held
  by the operator, offline. Everything else is kept on the platform's own vendor accounts, as the
  secrets deployed with the parts that read them -- never in a repository, and never in a store the
  platform itself runs, since what runs needs them to start.

**How content is cut, named and sealed is decided now**, since each is written into every piece of
data and a mistake in it is never undone, `scope.md`. Worked out with the author on 2026-10-17.

```
put(dataset, path, content)
  -> file id: keyed BLAKE3 over the whole file
  -> FastCDC cuts it into pieces; piece id: keyed BLAKE3 over each, before compression
  -> each new piece: zstd at level 1, kept only if smaller
  -> appended to the open container, sealed as it is appended
  -> closed at 16 MiB: sealed again in 64 KiB segments, placed among the scope's stores
```

- **A scope's salt is derived, never stored**, as BLAKE3's
  `derive_key(context, salt master || scope id)`. A scope's key is derived the same way, under
  another context, from the encryption master of a version. The organization's certificate carries
  both each week, RFC v7v3w, and they are the same every week: the certificate's own key pair
  rotates and has no part in them.
- **A context is `monoflake:{scope}:{type}:{version}`**, written into the code and never changed.
  Its words are whole, never abbreviated, of lowercase letters and digits alone, joined by a
  hyphen only where one word will not do, never by an underscore. A type is unique within its scope
  alone, and the code keeps them as one list. The version is a positive integer in decimal without
  leading zeros, raised by a change to what is derived, RFC wnqvu.

  | Context                         | Derived from                                                                                  |
  | ------------------------------- | --------------------------------------------------------------------------------------------- |
  | `monoflake:organization:salt:1` | the salt master and the scope id; at version 1 forever, since another would change every hash |
  | `monoflake:organization:key:1`  | the encryption master of a version and the scope id                                           |
  | `monoflake:journal:key:1`       | the organization's key and the journal's seed                                                 |
  | `monoflake:container:key:1`     | the organization's key and the container's seed, its journal's or drawn at random             |
  | `monoflake:organization:gear:1` | the scope's salt, for FastCDC's gear table                                                    |

- **Every layer's record is named by BLAKE3, in one of two modes.**

  | Named        | Over                                       | Mode            | Recorded as                                                     |
  | ------------ | ------------------------------------------ | --------------- | --------------------------------------------------------------- |
  | file         | the whole file, as it came                 | keyed, the salt | a path in a dataset -> its file id                              |
  | piece        | the piece, before compression              | keyed, the salt | a file id -> its piece ids                                      |
  | container    | the sealed container                       | unkeyed         | a piece id -> its container, offset, length, whether compressed |
  | stored block | each copy or parity shard a store is given | unkeyed         | a container id -> the stores holding it                         |

  What is plaintext is keyed, since anyone holding the content could otherwise compute its address,
  RFC 13ixj; what is sealed is not, since its hash tells nothing, so a container is checked and
  repaired with neither the salt nor the key. A file of one piece has one id for both. Kept as whole
  copies, a stored block is its container and has its id. **A store keeps a stored block under its
  id as 64 hex digits and nothing else**, no extension, since the magic says what it is, beneath two
  directories named by its first four: `/{aa}/{bb}/{id}`, so a store of a petabyte holds about a
  thousand in each. The footing keeps the id as 32 bytes.

- **Content is cut by FastCDC with normalized chunking at level 2** (USENIX ATC 2016, extended in
  IEEE TPDS 2020), into pieces of at least 256 KiB, about 1 MiB and at most 4 MiB: 22 effective mask
  bits before the 1 MiB and 18 after, the level its section 5.4 finds the sweet spot of
  deduplication at. It is written down by its definition and test vectors, never by a library's
  version, since two implementations that cut one byte apart deduplicate nothing between them. A
  file shorter than the least is one piece, so no other threshold says which files are cut. Its gear
  table is derived from the salt, since where content is cut tells what it is, and deduplication is
  within a scope already. **Its parameters never change**: changed, nothing breaks, but what is
  written after no longer deduplicates against what was written before.

  ```
  gear[0..256]  the first 2,048 bytes of derive_key("monoflake:organization:gear:1", salt),
                read as extended output; gear[i] is bytes 8i to 8i+8, little-endian
  from 256 KiB, hash = 0
  each byte b   hash = (hash << 1) + gear[b], wrapping at 64 bits
                cut after b when hash & mask == 0: before 1 MiB the 22-bit mask
                0x0000d93767537000, after it the 18-bit 0x0000d90707537000
  at 4 MiB      cut regardless; a rest no longer than 256 KiB is one piece
  ```

  The masks are those `fastcdc-rs` keeps for 22 and 18 bits, written into the code as constants.
  Test vectors are kept beside it: a fixed salt and input, and every cut they give.

- **A piece is compressed with zstd at level 1**, in a `content` dataset unless it is set otherwise,
  RFC 13ixj, and kept as it came when that is not smaller. Both
  hashes are taken before compression, so a level changed later changes no id.
- **A container is exactly 16 MiB, 16,777,216 bytes, and a piece never spans two.** Its header,
  256 segments and their tags fill it to the byte, 4,096 blocks of 4 KiB, so its size alone says it
  is whole and no length is written. It holds 16,773,079 bytes of pieces: it is sealed once the
  next piece would not fit, the rest zeros, so with pieces at most 4 MiB it holds at least 12 MiB of
  them. It is never sealed early; what has not filled one waits in the journal.
- **An `opaque` dataset's file is at most 16 MiB, and is placed as a container is**, RFC 13ixj,
  so a sealed container and a journal's object of the platform above both fit, RFC vr5lw:
  passed through raw, with no header, never cut, compressed or sealed and never through the
  journal, and placed as its dataset asks, as any container is. What it is -- sealed already or not,
  compressed or not -- is not the platform's to know, so it takes what it is given and keeps that;
  doing either again would only spend. Its dataset's kind, recorded in the footing, tells it from a
  sealed container, never its bytes: a container that could say it is unsealed would let whoever
  writes a store replace sealed content with its own.
- **Only what cannot fill a container goes through a journal.** A write that fills one is sealed in
  memory and placed at once, and answered once its stores have it, so bulk is bounded by the stores
  and never by the footing, `lessons.md`. Its seed is drawn at random, so one cut short before it is
  recorded leaves a container no record names, which a sweep removes after its grace, RFC vuanj.
- **What is to be sealed never leaves memory unsealed, and a journal is kept in the stores, never in
  the footing.** A scope keeps, for each placement it writes, at most two journals: one open,
  appended to only, and one frozen. A journal is placed as a container of its placement is, so what
  waits in it is as durable as its placement asks from the moment it is answered, and the footing,
  holding no journal, stays bounded, `scope.md`; it records only which journal each placement
  writes. Each write is sealed in segments of at most 64 KiB and put to the placement's stores as
  **one object**, `/journal/{journal}/{first segment}`, however many segments it holds; then one
  batch of the footing names its pieces, and the write is answered. Bytes go first and names after,
  as every write does, RFC vuanj, so a fault leaves at most an object nothing names, which a sweep
  removes.
- **A journal full is frozen and exported.** Once the next piece would not fit, the open journal is
  frozen, read only from then, and that piece goes on in a new one under a seed of its own; a write
  waits only while both are full, until the frozen one is exported. A frozen journal is read back
  from one of its stores into a compute, its pieces, compressed as they were written and never
  again, sealed whole as a container and placed first; then one batch records where its pieces are,
  and its objects are deleted. It is read back because a container is sealed again, under another
  key and in segments of its own, which no store's copy can do, `lessons.md`.
- **A container's format is named by its revision**, one byte of its header, an integer from 1 to
  255 stored as binary, RFC wnqvu, and authenticated with what it seals. A revision names the whole
  format -- the cipher, the segments, the nonce, the tag -- so any change to it is a new revision;
  one a reader does not know is refused, never guessed.

  | Revision       | Sealed by                                                      | State                                     |
  | -------------- | -------------------------------------------------------------- | ----------------------------------------- |
  | 1              | AES-256-GCM, 255 segments of 64 KiB and a last of 61,399 bytes | the one built                             |
  | 2              | ChaCha20-Poly1305, otherwise as 1                              | defined, and refused as reserved, unbuilt |
  | 0 or any other | undefined                                                      | refused                                   |

  A reader that meets 2 answers that the revision is reserved and unsupported, an error of its own,
  and never calls a cipher for it.

  Native code seals with a library that reaches the CPU's AES instructions, a web runtime with its
  own WebCrypto; where a CPU has none, the same bytes are computed in software, more slowly.

- **Each container is sealed under a key of its own**, `derive_key("monoflake:container:key:1",
organization key || seed)`, so the same header always gives it back. Its header is 41 bytes, and
  nothing but segments follows:

  | Offset | Bytes      | Field                           | Value                                                                   |
  | ------ | ---------- | ------------------------------- | ----------------------------------------------------------------------- |
  | 0      | 4          | magic                           | `MNFL`                                                                  |
  | 4      | 1          | revision                        | 1                                                                       |
  | 5      | 4          | the encryption master's version | a 32-bit integer, big-endian, at least 1                                |
  | 9      | 32         | seed                            | drawn at random                                                         |
  | 41     | 16,777,175 | segments                        | 255 of 65,536 bytes and one of 61,399, each sealed with its 16-byte tag |

  Segment i is sealed with the nonce `8 zero bytes || u32_be(i)` and the associated data
  `header || u32_be(i) || final`, `final` being `0x01` for segment 255 alone and `0x00` for every
  other; the associated data is rebuilt as it is read, never written. No nonce repeats however many
  containers a scope writes, and a container is read whole.

  **A journal draws its seed once, as it is opened**, and is named by it, 64 hex digits; its first
  object begins with the revision and the master's version. Its segments are sealed as a
  container's are, under the journal's key, each the next index and `final` `0x00` throughout, its
  end what the footing records.
  The container it becomes takes the same seed under the container's key, so the two keys differ
  while every row and segment counts from zero, and **a journal exported again gives the same
  bytes, and so the same id**: a container placed but not yet recorded is placed again over itself,
  never left behind. **A key seals one content**: sealing the same bytes again under the same nonces
  tells nothing, and whatever else is sealed draws a new seed.

- **A container's place is computed, by rendezvous hashing over integers alone.** Among the stores
  that meet its placement, each store s scores the container by the highest, over k from 0 to its
  weight less one, of the first 8 bytes, read big-endian, of
  `derive_key("monoflake:container:placement:1", container id || store id || k)`: the container's
  32 bytes, the store's id as 4 bytes big-endian, k as one byte. The copy or shard i goes to the
  store ranked i, a tie to the lower store id. A weight is an integer from 1 to 255, so a store is
  chosen in proportion to it, exactly, and never through a float, whose last bit two platforms may
  compute apart and so look for a container where it is not. The store's id is hashed, never its
  address, so a store's address or secret changed moves nothing.
- **Deletion marks, and collection reclaims.** Deleting a file marks it and changes no container. A
  piece is dead once no file names it, by a count of those that do, and a container's dead share is
  what its dead pieces take of it. Collection repacks a container's live pieces into a new one, in
  three ways:

  | Way        | What it does                                                                                           | Changes data |
  | ---------- | ------------------------------------------------------------------------------------------------------ | ------------ |
  | inspect    | counts each container's dead share and what collecting would reclaim                                   | no           |
  | collect    | repacks what it is pointed at, now, at any threshold; at zero, erases what was deleted                 | yes          |
  | automatic  | repacks a container once a deletion's mark is written and its dead share passes 30 percent, unless set | yes          |
  | background | walks every container, one at a time and each its own atomic step, repacking below the threshold too   | yes          |

  **A deletion is answered once its mark is written**: the repack it may start is a task of its
  own, and never holds the deletion back. A repack's live pieces take a write's way: what fills a
  container is sealed at once, and the rest goes into the journal. What the background walk repacks,
  and how often, is to be decided. [D6]

  A piece a write finds again is counted again in the same step as it is found; a repack drops only
  pieces still at zero when it commits, and the old container is removed only after. The threshold
  trades space for rewriting: at 30 percent, each byte reclaimed costs about 2.3 rewritten.

Open, for the discussion that follows:

- Which three places, all offline and the operator's, hold a master's shares. [B12]
- What the control plane is and how far it reaches, the name reserved for it. [B10]
- How much an organization writes through its footing before the footing is what bounds it. [C7]
- How stores are added to a scope, which is to come down from what the layers above need. [C3]
- How the extent is kept off the footing's growth, since a footing is bounded, `scope.md`: its pages
  in containers, the footing keeping their root. [B17]
- How often the operator rotates the intermediate key, and how long a working key lives. [D3]
- Whether a system apart from the platform -- a machine the author keeps, signing on the author's
  authority -- may rotate the intermediate key unattended in the operator's place. [D3]
- How a leaked intermediate key is revoked, while every part holds the root's public key alone; a
  failure, and so s1's. [D3]
- Whether a name that must be unique across scopes, such as an app's domain, is the platform's
  record, and whether it is kept in the anchor or beside it. [B9]
- How a host keeps its way to a footing short, where the vendor's routing lands a connection far:
  one connection dialed again while it lands far, reads from replicas, a paid plan's routing
  measured; an optimization, not a block. [D5]
