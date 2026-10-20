---
name: 'Storage Is Named Content'
title: 'An organization keeps files by path in file buckets and objects by hash and extension in object buckets, both naming content addressed by a hash keyed to the organization, and serves an object bucket alone'
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

**An organization's storage holds buckets of two types, and content beneath both**, worked out
with the author on 2026-10-18. A bucket of either holds names alone; the bytes are content's.

```
storage (one an organization, its own unique salt)
  file bucket     {path}/.../{path}/{file} -> hash     names the app chooses, changed by a write
  object bucket   {hash}.{extension}       -> hash     names the content gives, never changed
  ---------------------------------------------------- beneath, and invisible to an app
  content         hash -> its pieces, RFC b8f35
```

- **A file bucket is files by path**, each written and read whole, and no versioning, which a
  client that speaks S3 reads and writes through a bridge, an object bucket being only read there,
  RFC vr5lw. It is never served: what is shown outside is an object, published from it.
- **An object bucket holds objects named by their content.** An object is a hash and an
  extension, `{hash}.{extension}`, the least a name can carry: an app gives content and an
  extension, never a name, a path or a media type, and the platform computes the hash. **The same
  content under two extensions is two objects**, its bytes kept once, so an extension given is never
  lost to one given before. An object is never changed: written again under its extension, it is the
  object already there. An object with no extension is `{hash}` alone.
- **Content is shared by every bucket of an organization**, and deduplicated across them: a file
  and an object of the same bytes name one content. Content is collected once no file and no object
  names it.
- **A bucket's id is drawn from the one space of its organization's resources**, RFC b8f35, and
  carries its type: an operation on a bucket of the other type is refused as `rejected`, saying so.
- **A bucket is one level only and never nested.** It is the scope of a policy: its placement, its
  kind, a quota, who may bind it, a description, and deletion of the whole. A component that needs
  another policy is another bucket.
- **A bucket's policy is chosen by its kind, never set flat**: what a kind lacks cannot be set.
  `packed`, the default, is cut and deduplicated, and compressed and sealed unless set otherwise,
  RFC b8f35. `opaque` is passed through raw, each file or object at most 16 MiB -- never cut,
  compressed or sealed, since whether it is either already is not the platform's to know -- as
  what a platform above seals is, RFC 94y0d. The placement, the quota, who may bind it and the
  description are every kind's. The two are named for what is done to the bytes, worked out with
  the author on 2026-10-19: `packed`, its pieces packed into parcels, RFC b8f35, and `opaque`, left
  as they came; content names what lies beneath every bucket of either.
- **A bucket's placement says what its data needs, and each store says what it is**, declared by
  whoever binds it as it is bound, RFC b8f35; the platform places each parcel only on stores
  that meet every need. **Every attribute is ordered**, so content named in several buckets is held
  to the highest of each that any of them asks.

  | Attribute    | Asks of a store                            | Levels, lowest first                                                                | A bucket's default |
  | ------------ | ------------------------------------------ | ----------------------------------------------------------------------------------- | ------------------ |
  | availability | how surely it can be reached               | `opportunistic`, `best_effort`, `stable`, `recoverable`, `redundant`, `multiregion` | `best_effort`      |
  | durability   | how surely what it holds lasts             | `ephemeral`, `persistent`, `redundant`, `replicated`, `multizone`, `multiregion`    | `persistent`       |
  | custody      | whether the organization alone controls it | `false`, `true`                                                                     | `false`            |

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
  API, `best-effort` in a derive context, and in code as its language names things. A set of
  stores is of the level its members compose to, by RFC vr5lw's rules, and a host is of these levels
  as a store is.

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
  cannot meet it; a store is removed only while every bucket's placement still holds without it.
  What follows when a store is lost without warning, or reaches an end its owner did not choose, is
  to be decided. [C20]
- **A bucket not sealed and placed on a store outside its organization's custody is in a warning**,
  kept as a field and never refused: never dismissed, shown on the bucket's own page and as it is
  created, and nowhere else.
- **A description is free text**, empty unless written, and changed at any time.
- **A bucket's record is `bucket` in `model/contracts/`**, worked out with the author on
  2026-10-19: its type fixed as it is made, its kind, placement, spread, quota, access and the apps
  that may bind it. No name: a bucket is its id, and its name shown is its organization's tree's,
  RFC v7v3w. The warning of a bucket unsealed off its custody is computed from its placement and
  kind, never kept, since it is never dismissed.
- **One or many apps may bind a bucket.** An app holds no state; it knows a bucket and the names
  it writes in it, nothing beneath.
- **A path is a key split by `/`**, so a directory is only a prefix and a file may sit at the top,
  `(bucket)/{file}`. The app names files freely.

**What an app can do:**

| On                          | Operation                                                                                         |
| --------------------------- | ------------------------------------------------------------------------------------------------- |
| bucket                      | `create` with its type and policy, `describe`, `list`, `delete` (only while empty): configuration |
| file, in a file bucket      | `write(bucket, path, content) -> {hash, size}`, `read`, `describe`, `list(prefix)`, `delete`      |
| object, in an object bucket | `write(bucket, content, extension) -> object`, `read`, `describe`, `list`, `delete`               |
| publish                     | `publish(file bucket, path, object bucket) -> object`, the content the path names at this moment  |

- **A bucket is configuration; a file and an object are data.** Creating or deleting a bucket
  changes the organization's configuration, through its organization's own control, which an app
  may call as any client does, RFC v7v3w; a file's and an object's operations are the data plane's.
- **A file's name points at content; content never changes.** Writing a path again points it at
  new content, and a write may be conditional on the hash it last saw, so two writers never
  silently overwrite each other. A directory is never renamed.
- **Creating a path and replacing one are separate rights.** A write to a path that exists is a
  replacement, which can lose what it pointed at as a deletion can; one allowed to create alone is
  refused there, so a file bucket can be written only forward -- a backup, an audit log -- by a
  function that, taken over, could add and never erase. An object bucket is written only forward
  by its nature, since nothing in it is ever replaced.
- **Content is addressed by its hash, keyed to the owner** -- BLAKE3 keyed by the owner's salt,
  RFC b8f35. The same content stored twice within one owner is stored once, across buckets and
  apps alike; across owners the same content has a different hash, so an address cannot be computed
  by anyone outside the owner, and nothing is shared between owners.
- **`publish` puts a file's content into an object bucket by its hash**, and moves no byte: the
  object is the content the path names as it is called, under the path's extension: a compound one
  of the table below where the path ends in one, `a.tar.gz` giving `tar.gz`, and otherwise
  everything after its last dot, `app.min.js` giving `js`.
- **A path is held to no rule of an extension, and an object's extension to every one**, worked out
  with the author on 2026-10-19: a file bucket names files as the app likes, and a path whose
  extension breaks an object's rules is published bare, `{hash}`; `write` to an object bucket is
  given its extension by the caller, and refuses one that breaks them as `rejected`, saying which
  rule. Content beneath has no name either way, so it is deduplicated alike.
- **An object's extension is written in ASCII letters, digits and dots alone**, at most 16
  characters, RFC vuanj; a hyphen, an underscore, a space, a letter outside ASCII, and a dot
  leading, trailing or doubled break it. Between, a dot stands anywhere: `write` takes `min.js` as
  it is given.
- **The platform keeps a table of compound extensions** -- `tar.gz`, `tar.bz2`, `tar.xz`,
  `tar.zst`, a tar compressed -- which `publish` reads to take a path's extension, since a path's
  other dots are a name's habit, `app.min.js`, and no format. It only grows, as the spellings'
  below.
- **An extension is made standard before it names anything**, by `write` and `publish` alike, so
  one format reaches one object by either: lowered to its small letters, then its last part, the
  format, rewritten by the platform's table of spellings, one spelling of each format kept, so
  `min.jpg` is `min.jpeg`. **That table holds spellings of one format alone**, never types that
  are only served alike, so `ini` is never `txt`; it is written by hand, and as it is part of an
  object's name a row once written is never changed or taken out, though rows may be added. An
  extension it does not know is kept as it came.
  - **A spelling is rewritten to the format's full one**, since the short ones are mostly cut to three
    letters by file systems that once allowed no more, `docs/lessons/`, worked out with the author on
    2026-10-19: `jpg` and `jpe` to `jpeg`, `tif` to `tiff`, `htm` to `html`, `xht` to `xhtml`, `mht`
    to `mhtml`, `mpg` and `mpe` to `mpeg`, `mid` to `midi`, `aif` to `aiff`, `pct` to `pict`, `yml`
    to `yaml`, `sgm` to `sgml`, `djv` to `djvu`, `igs` to `iges`, `stp` to `step`; and a tar's
    `tgz` to `tar.gz`, `tbz2` and `tbz` to `tar.bz2`, `txz` to `tar.xz`, `tzst` to `tar.zst`.
  - **Unless the short one is what the world recognizes**: `markdown` to `md`, `text` to `txt`,
    `wave` to `wav`.
  - **A pair alike in spelling but not one format is never joined**: `svgz` is `svg` compressed,
    `aifc` is `aiff` compressed, `smi` is SAMI captions as well as SMIL, `xsl` is XSL-FO as well as
    XSLT. A pair whose recognized spelling is unsure, `3gp` and `3gpp`, waits: a row left out costs
    one content a second name, a row wrong is wrong for good.
- **An object's media type is never stored**: it is the extension's, looked up as the object is
  served, in a short table of the extensions the platform knows; every other is served as
  `application/octet-stream`. This table is how a browser is answered and never part of a name, so
  it changes at any time, its cost an answer cached a year. One extension gives one type, and many
  give the same, so a type never leads back to an extension. An extension of several parts is
  served as its last part's type, `tar.gz` as `gz`'s and `min.js` as `js`'s. Each type is IANA's where IANA
  registers one, MDN's where it does not, `docs/lessons/`; one a browser cannot show is listed all the
  same, since showing nothing harms nothing. The table it starts with:

  | Of    | Extension -> type                                                                                                                                                                                                                                                                      |
  | ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
  | image | `png` `image/png`, `jpeg` `image/jpeg`, `gif` `image/gif`, `webp` `image/webp`, `avif` `image/avif`, `apng` `image/apng`, `jxl` `image/jxl`, `bmp` `image/bmp`, `ico` `image/vnd.microsoft.icon`, `tiff` `image/tiff`, `heic` `image/heic`, `heif` `image/heif`, `svg` `image/svg+xml` |
  | audio | `mp3` `audio/mpeg`, `m4a` `audio/mp4`, `aac` `audio/aac`, `ogg` `oga` `opus` `audio/ogg`, `flac` `audio/flac`, `wav` `audio/wav`, `weba` `audio/webm`                                                                                                                                  |
  | video | `mp4` `video/mp4`, `webm` `video/webm`, `ogv` `video/ogg`, `mov` `video/quicktime`                                                                                                                                                                                                     |
  | font  | `woff2` `font/woff2`, `woff` `font/woff`, `ttf` `font/ttf`, `otf` `font/otf`                                                                                                                                                                                                           |
  | text  | `txt` `text/plain`, `md` `text/markdown`, `csv` `text/csv`, `tsv` `text/tab-separated-values`, `vtt` `text/vtt`, `html` `text/html`, `css` `text/css`, `js` `mjs` `text/javascript`                                                                                                    |
  | data  | `json` `application/json`, `xml` `application/xml`, `xhtml` `application/xhtml+xml`, `wasm` `application/wasm`, `pdf` `application/pdf`                                                                                                                                                |

- **An object bucket alone is served**, at `/v{n}/storage/{bucket}/{hash}.{extension}` of a name
  bound to the storage, its organization's gateway's or one the organization binds, RFC vr5lw; its entry
  delivers the path to the storage unread. The version is an integer, `v1` now, written with its
  `v` in the path alone; only that spelling answers, the version's and the hash's, 64 lowercase hex
  digits, RFC b8f35. It is answered with a strong `ETag`, `immutable` and a year's cache, public or
  private.
  - **Who may read is the bucket's**, decided by who asks, never by a parameter on the URL, so the
    address stays one. Since the URL names its bucket, the same content in a public bucket and a
    private one has a URL in each, each answered as its own bucket says. How a reader proves they
    may read a private one is open. [C10] Content made public cannot be recalled from caches the
    platform does not hold.
  - **An object is served as its extension's type, its bytes never read to tell it**, with
    `X-Content-Type-Options: nosniff`, so the browser never guesses. HTML, SVG and a script are
    served as themselves too: what keeps them harmless is the next rule, never a type that lies,
    which would break an SVG in an `<img>` and a script a page of another domain loads.
  - **Every answer carries `Content-Security-Policy: sandbox`**, but a type exempted, worked out
    with the author on 2026-10-19: what is opened as a page then shows and does nothing, its origin
    opaque, with no script, no cookie, no form sent and no window opened, so what an app's user
    uploads can never act as the organization's. A response's policy reaches only the document made
    from it, so a script, a stylesheet, an image or a font loaded by a page elsewhere is untouched,
    `docs/lessons/`. **The exemptions are listed, never the dangers**, so a type a browser learns to
    run tomorrow is sandboxed already: `application/pdf` alone, which Chrome shows blank in a
    sandbox.
  - **A public bucket's answers carry `Access-Control-Allow-Origin: *`**, since a module script, a
    font and a `fetch()` from another domain need it; a private one's is [C10]'s.
- **Exported, an object bucket is laid out as `/{aa}/{bb}/{hash}.{extension}`**, the first four
  digits of the hash as two directories, as a store keeps a stored block, RFC b8f35, so it moves
  into any other object store or file system as it is; a file bucket is exported as its paths.
  Content is never exported, so it has no layout. An export is plaintext, and is a right of its
  own; when it is built is later. [D12]
- **Content held for buckets with different policies is held to the strictest of them**, the
  highest of each attribute any of them asks.

**Beneath the app, and invisible to it, is the storage's own metadata**: an organization's buckets,
each file bucket's paths and each object bucket's objects and the hash each names, the content's own
metadata, and the access each bucket grants. Writing a path updates every directory above it up to
`/` in the same step, so a directory's size and count are read, never computed, when it is listed.

Open, for the discussion that follows:

- Whether that metadata is held per owner or per bucket. Deduplication and the count of names
  pointing at each hash are an owner's, which argues for per owner. [C9]
- Whether one content named in a `packed` and an `opaque` bucket is kept once, and how. [C8]
- What follows when a store is lost without warning, or reaches an end its owner did not choose.
  [C20]
- Whether copies are laid out whole or as shards with parity, and whether the owner sees which.
  [C21]
