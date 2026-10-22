---
name: 'Code Follows the Model'
title: "The platform's code is cut where the model is: a component is a deployable in one language of three, a library a package of one language, and only an edge between processes is a wire contract"
status: landed
supersedes: []
blocked-by: []
commits:
  - monoflake/platform@24e60378
  - monoflake/platform@6b6cfa87
  - monoflake/platform@44a6e6c1
  - monoflake/platform@634bc1d1
  - monoflake/platform@2561c1a0
  - monoflake/platform@06d73ddf
  - monoflake/platform@ab48c6aa
  - monoflake/platform@a3c65752
  - monoflake/platform@c1831e64
references:
  - url: https://www.rfc-editor.org/rfc/rfc8949
    took: "CBOR's deterministic encoding, its 4.2, and its appendices' items as tests"
  - url: https://www.rfc-editor.org/rfc/rfc9052
    took: "COSE's Sign1, held to its standard's tests"
  - url: https://www.rfc-editor.org/rfc/rfc8392
    took: 'CWT, held to its Appendix A'
  - url: https://github.com/cose-wg/Examples
    took: 'the sign1, EdDSA and CWT cases an implementation is held to'
  - url: https://docs.rs/minicbor/latest/minicbor/
    took: "minicbor, Rust's CBOR, wrapped"
  - url: https://www.rfc-editor.org/rfc/rfc4648
    took: 'base64url without padding, the one text of bytes'
  - url: https://tailscale.com/opensource
    took: 'the server that coordinates kept apart and the rest opened'
  - url: https://rescript-lang.org/community/roadmap/
    took: 'ReScript 13 writing .d.ts, genType until then'
  - url: https://github.com/cloudflare/workerd
    took: 'one JavaScript bundle running alike on a Worker and in workerd'
---

## Question

How the platform's code is to be written, before any of it is: its languages, where one meets
another, and what crosses between them. Worked out with the author on 2026-10-19, on this project
alone, apart from the workspace's present rules and every other project; what changes in those when
this lands is for then.

The shape the discussion has reached so far:

## Decision

**The model's boundaries are the code's**, since `model/graph/` already cuts the platform into
components, libraries and edges, each with its contract:

| In the model                              | In the code                                                              |
| ----------------------------------------- | ------------------------------------------------------------------------ |
| a component, `model/graph/components.res` | a deployable -- a process, a Worker, a binary -- written in one language |
| a library, `model/graph/libraries.res`    | a package of one language, used by every component of it that needs it   |
| an edge                                   | an interface between two components                                      |

- **An edge within one process is a call**, never serialized: ReScript compiled to JavaScript calls
  a library of JavaScript's, and is called by it, in one memory.
- **An edge between processes or hosts is a wire contract**, and only it. **Each names the one it
  carries**, decided by the author on 2026-10-20: an interface, a signed record, a bundle's
  section, a footing's record, an app's own WIT, or one not yet declared, filed with the row that
  declares it, `model/checks/design/crossing.res`; an edge to the ground carries the vendor's, and
  one to a boundary not yet drawn its boundary's. [B32]
- **A browser computes nothing of the platform's**: a page draws what its API returns. So what a
  server and a browser share is the contracts alone, generated, and no logic is written to run in
  both. Logic that components of
  two languages both need is written in each and held to one set of cases kept beside it.
- **The rules the model checks of its graph are the code's rules of dependency** -- a `hard` edge
  points to its own layer or below, a library uses libraries alone -- so the check proves the code's
  boundaries where the code keeps the model's.

**What a user runs is MIT OR Apache-2.0, and what stands it up as the hosted platform is kept
apart**, decided by the author on 2026-10-20, replacing an AGPL-3.0-only control plane decided
earlier that day. The platform half, which fills this half's roles, with the hosted platform's
configuration and its operation, is the private `monoflake/cloud`'s and no directory here, RFC
8lkuv;
every other component, `control(organization)` among them, every driver and every library is MIT
OR Apache-2.0, `model/graph/components.res`. So a team can stand its own platform up from this
repository with a little glue of its own, and the glue and the running of it are what the hosted
platform offers -- as Tailscale keeps its coordination server and opens the rest, a bet that most
would rather use it than write and run their own. The root holds the two texts as Rust's projects
do, `LICENSE-MIT` and `LICENSE-APACHE`, and a manifest declares its package's,
`model/checks/layout/code.res`.

**A language is chosen by three measures, in order**, worked out with the author on 2026-10-19:

1. **What is bound by the CPU is Rust**, near C's speed and collected by nothing.
2. **What needs memory that is predictable is Rust**: that is a question of whether what
   orchestrates may be collected, so where it may not, the orchestration is Rust too.
3. **The rest is written where it is easiest to write**: where JavaScript runs, a language of its
   ecosystem; on a machine, a native one, since a JavaScript runtime carried onto a machine is a
   cost of its own.

| Runs                                                       | Language   | Its server    |
| ---------------------------------------------------------- | ---------- | ------------- |
| natively on a machine: its driver, RFC vr5lw, and the rest | Rust       | axum on tokio |
| as JavaScript: on a Worker, in `workerd`, in a browser     | ReScript   | Hono          |
| as glue, where a library's surface is too wide to bind     | TypeScript | --            |

- **A component on a machine is Rust whole, its orchestration among it**: its libraries are Rust already,
  and a build that keeps every library's compiled output in a cache rebuilds only the component, within
  two or three times a JavaScript build's seconds, the author's estimate, to be measured once code is.
- **What the platform writes to run as JavaScript is ReScript**: of ML's family, its types sound, so
  no `any` passes its compiler. Its ceiling is TypeScript's, since both end as JavaScript, and its
  floor is the compiler's, never the writer's. A library taken from npm is as safe as whoever wrote
  it, whatever its language; ReScript is the floor of what the platform writes, and what it publishes
  to npm carries that floor to those who call it.
- **The platform's first party is Rust and ReScript alone**, decided by the author on 2026-10-19,
  so every business edge is between them. **TypeScript is glue and nothing more**: written only where
  a library's surface is so wide that binding it in ReScript costs more than a shim, with JavaScript,
  JSDoc and Svelte beside it where a page asks.
- **ReScript's edge is kept as Rust's `unsafe` is**, worked out with the author on 2026-10-19:
  - **The platform's own logic is ReScript**, and calls itself freely within, so all inside the edge
    is proven by the compiler.
  - **A library of JavaScript's is taken in its own language**: one of standing, Hono's kind, is no
    safer for a skin of ReScript over it, and may be better than ReScript written in haste.
  - **Its bindings stand together at the edge**, one module a library, and are what is taken on
    trust, as an `unsafe` block is.
  - **The edge is drawn where crossings are fewest**, never through a library's busy interface:
    Hono's app is a fetch handler, so its binding is a few calls, and a request crosses once.
  - **A crossing copies little**: ReScript's records, arrays and strings are JavaScript's own, so
    they pass as they are; a variant, a list or an option within an option has a form of its own and
    is converted at the binding. TypeScript reads ReScript's exports by genType until ReScript 13
    writes `.d.ts` itself, `docs/lessons/`.
- **OCaml is not written**, decided by the author on 2026-10-19. It was chosen so one library might
  run natively and, by Melange, as JavaScript; a browser computing nothing leaves that unasked, and
  what stays is a third native toolchain -- opam, dune's package management, which calls itself not
  final, Eio -- beside Rust's. ReScript keeps OCaml's types where JavaScript runs and rides npm,
  `docs/lessons/`.
- **A component on a Worker is never Rust compiled to WebAssembly**: a Worker's ground is JavaScript,
  Rust there crosses into it by copying at every call and runs without tokio, and a machine's
  JavaScript component runs in `workerd`, so one bundle runs on both, vr5lw.
- **ReScript is never written inside a `.svelte` file**, which it does not read; a page's logic is a
  `.res` module the page imports compiled.
- **ReScript's `int` is 32 bits**, so an integer past it crossing into it is a `float`, exact
  within 2^53, the most the platform's contracts hold.
- **A library that runs as JavaScript runs on a Worker, in `workerd` and in a browser alike**, so it
  uses the web's standard APIs alone, never node's; I/O stands at a component's edge.
- **The tools are cargo, node, ReScript's compiler, vite and tsdown on rolldown, oxlint and oxfmt**,
  and TypeScript 6 and 7 side by side.

**The model and the code are one repository**, decided by the author on 2026-10-19, so the check
reads the code it holds to the model's boundaries, `model/contracts.json` reaches its generators
unpublished, and a change to both is one commit. Its top is six directories: `model/`, the spec;
`code/`; `docs/`, what is read; `tests/`, the samples every implementation is held to; `scripts/`,
the entries that drive the rest; and `vendor/`. **The samples stand apart from what runs them**,
decided by the author on 2026-10-19: `tests/` holds what is tested, by subject, as data any language
reads, and `code/tools/` the runner, which holds no sample.

**A component's code is placed by its layer, in a directory named as the model names it**, worked out
with the author on 2026-10-19, so where code goes follows from the model and is never argued again:

| `code/`       | Layer | Holds                                                       |
| ------------- | ----- | ----------------------------------------------------------- |
| `apps/`       | 1     | the platform's own apps; a user's are not here              |
| `products/`   | 0     | the three products and the control that configures them     |
| `primitives/` | -1    | the five components the products are built from, RFC vuanj  |
| `substrate/`  | -2    | what those stand on: backings, the extent, hosts, drivers   |
| `platform/`   | -3    | the platform half, layer -3, whose code is not here, 8lkuv  |
| `libs/`       | --    | the libraries, placed by subject, a library having no layer |
| `tools/`      | --    | programs run while the platform is built: the generators    |

- **A half is never a directory**, since the layers already part them: layer -3 is the platform's
  half and every layer above it the organization's, so `control(organization)` is
  `products/control`.
- **A library's languages are a property the model declares, never a directory**: a library is
  one subject, and one written in two languages is one directory holding each language's
  manifest beside the other's, decided by the author on 2026-10-19 with `envelope`, the
  contracts' types and their encoding, which cargo and ReScript each take as their own package
  there. Its generators are one tool so too, `code/tools/envelope-generator/`, each written in
  the language it writes; the tool is named for what it does, as the library holds the subject's
  name, decided by the author on 2026-10-20.
- **Each component declares its language in the model**, decided by the author on 2026-10-19, and
  the language follows from where it must run: ReScript for what must run on a Worker, which then
  runs in `workerd` on a machine alike, and Rust for what runs only natively on a machine. Since an
  organization's resources may be Cloudflare's, every component is ReScript; an app's code is its
  user's and the root runs nothing, so neither declares one. **Where the platform meets a vendor, a
  kind is a contract with an implementation a vendor**, and the language is the implementation's:
  a driver declares none, and lies as a directory of its implementations, `driver(machine)`'s Rust
  and `driver(cloudflare)`'s ReScript, RFC vr5lw. **The drivers lie together in `substrate/driver/`**,
  decided by the author on 2026-10-19, each named `driver(...)` with its vendor in parentheses, as
  `control(organization)` names what it is first and which after, decided by the author on
  2026-10-20, so its directory is that name, `driver/cloudflare` and `driver/machine`, and no word is
  said twice. **A name is written whole**, never shortened.
  `model/checks/layout/code.res` holds that each component's code lies in its layer's directory, named as
  the model names it, that its manifest is its language's, and that it uses only libraries of its
  own language.

**The tree builds as three workspaces at its root**, decided by the author on 2026-10-19:

- **The root holds their manifests and no package**: `Cargo.toml`, a virtual manifest, its members
  listed one by one, `[workspace.package]` and `[workspace.dependencies]` shared, one `Cargo.lock`
  and one `target/`; `package.json`, the tools; `pnpm-workspace.yaml`, taking all beneath `code/`;
  and `rescript.json`, the model its own sources. **Neither of the last two lists a block**,
  decided by the author on 2026-10-20, so the model compiles alone and each package builds as its
  own root, one failing failing no other: a package therefore writes its own module format and
  suffix, `docs/code.md`. Cargo takes no recursive glob, so `model/checks/layout/workspace.res`
  holds its list to what is there.
- **A package is named as the model names what it holds**: a component by its name, a half
  written after a hyphen, `control-organization`; a driver's implementation and its management
  by the driver's name and theirs, `driver-machine-object`, `driver-machine-management`; a library
  by its subject. A ReScript package is `@monoflake/` led in its `package.json` and its
  `rescript.json` alike, which pnpm links it by, and **namespaced**, so two packages' modules of one
  name never meet. Its sources are `src/`; a setting such as its warnings is its own to write, as
  ReScript inherits none. `model/checks/layout/code.res` holds the names and the manifests.
- **A driver holds its management beside its implementations**, `management/`, in the language
  its ground asks, `model/ground/drivers.res`: the process that answers the management interface
  and hands each call to the implementation of its kind.
- **What is generated is never committed**: `model/contracts.json` is the one product committed,
  and an envelope generated from it would be a second copy to drift. A build writes it again
  first, then compiles ReScript, then cargo, then bundles each Worker by tsdown; the order is a
  script's, `scripts/`. **Rust's is written by the library's `build.rs`, into cargo's `OUT_DIR`,
  and ReScript's by `mise run generate`, into the library's `generated/`**, decided by the author on
  2026-10-20, so cargo builds alone, and `mise run prepare` readies a fresh clone. Every output -- `.res.mjs` beside its source,
  `target/`, each package's `dist/`, `generated/` -- is ignored.

**A wire contract encodes as JSON for an API, and as CBOR for a record of the footing, a bundle and
a claim of a CWT**, in one shape a contract at a time, its CBOR deterministic by RFC 8949's 4.2.

**A wire contract is declared in the model, and the model writes it out**, worked out with the
author on 2026-10-19:

- **The model is written in ReScript**, decided by the author on 2026-10-19: nothing consumes it
  yet, so it is cheapest now, and its sum types state the subset below exactly. It is ported first
  as it stands, and the port holds when its check prints the same, byte for byte.
- **What is structural is derived, what is business is declared once**: a record's shell -- kind,
  id, generation, version -- a reference between records, typed by what it refers to, and which
  contracts must exist, one for every edge between processes, follow from the graph; a record's own
  fields and a call's input and answer are declared in the model, once.
- **The model writes one product, `model/contracts.json`**, by `mise run check --write`, committed: every contract in the subset below,
  each type's JSON and CBOR fixed in it. It is the one thing a language reads. Nothing reads the
  model's code, ReScript's consumers among them, so the model may change, or change its language,
  without them.
- **Rust and ReScript each generate their envelope from it** -- the types, their encoding and their
  decoding -- by a program of each language's own; past the envelope each language writes as it
  likes, and nothing within is asked to match the other.
- **The check guards it**: an edge between processes names its contract; a field removed or changed
  without its contract's version raised fails against the product committed; a reference names a
  record that exists.
- **WIT stays the language of an app's exports**, RFC 49qyg: the platform's own contracts are the
  model's, WIT its users'.

**The subset is what both languages hold natively, and no more**:

| Shape                                               | Rust                       | ReScript                   |
| --------------------------------------------------- | -------------------------- | -------------------------- |
| a boolean, a string, a 64-bit float                 | `bool`, `String`, `f64`    | `bool`, `string`, `float`  |
| a signed 32-bit integer                             | `i32`                      | `int`                      |
| an unsigned one, as an id, b8f35                    | `u32`                      | `float`, exact             |
| one under 2^53, a time in milliseconds or a size    | `u64`, checked below 2^53  | `float`, exact             |
| bytes, base64url unpadded in JSON, RFC 4648's 5     | `Vec<u8>`                  | `Uint8Array.t`             |
| a content's hash, 32 bytes; 64 hex digits in JSON   | `[u8; 32]`                 | `Uint8Array.t`             |
| a record, a field absent when it has nothing to say | a struct, `Option` fields  | a record, optional fields  |
| a closed set of names                               | an enum without data       | a variant without payloads |
| a union tagged by a field, with payloads            | an enum, tagged internally | a variant under `@tag`     |
| a list; a map keyed by string                       | `Vec`; `BTreeMap`          | `array`; `dict`            |
| a signed integer within 2^53, a number in JSON      | `i64`, checked within 2^53 | `float`, exact             |
| a set of names, each a bit, an integer in CBOR      | `u32` with a constant each | `array` of a variant       |
| a secret, written as bytes are                      | `Vec<u8>`                  | `Uint8Array.t`             |

Left out: generics, functions, `null`, and whatever one language alone has, decided by the author
on 2026-10-19 with the four below, from the bucket's trial, `model/contracts/`. **A secret is a
shape of its own**, decided by the author on 2026-10-20: written as bytes are, sealed under its
control's key where it is kept and plain only in the call that hands it to what uses it, so the
model sees where every one lies and refuses one that a signed record or a bundle's section reaches. **An integer of 64
bits is left out**, decided by the author on 2026-10-20: a database's integer is held within 2^53
either way, as a JavaScript number holds one exactly, so it is a number in JSON as every other is.
What asks more than that is an identifier or a hash -- a snowflake id, a 64-bit fingerprint, a time
in nanoseconds -- never a sum, and is kept as text or bytes, as the services that hand such ids out
already write them. A Durable Object hands JavaScript every SQLite integer as a double and D1
rounds past 52 bits, `docs/lessons/cloudflare.md`, so a wider integer would be either a wrapping on
every query of those or a value coerced unseen; one read past the range fails instead, as
`beyond_range`, on every implementation alike, a machine's among them, so a database moved keeps
its answers.

**An interface is a set of operations in the subset**, decided by the author on 2026-10-19 with the
database's interface: each operation its input and its output, records declared, and the reasons it
may fail for, each a failure of RFC 49qyg's -- `rejected`, `unavailable` or `unknown` -- that a
caller acts on, the reason only told. Three reasons are every operation's and declared by none:
`denied`, a credential missing or wrong; `malformed`, an input that does not parse; and
`overloaded`, an implementation that cannot answer for a moment, `unavailable` and worth a retry,
since a database's one writer keeps its callers from meeting a lock, and what is left is load. An operation is reached at `POST /{interface}/{operation}`,
its body a call, its output or an `error` the answer, JSON or CBOR by the request; an
interface's version is raised as a record's is, and the check refuses an operation gone or a type
it reaches changed while the version stayed. **The platform's own interfaces are all of the
subset**, a kind's and the database's among them; WIT is an app's alone.

- **A call is every operation's body, and carries what it acts by**, decided by the author on
  2026-10-20: the interface and the operation it reaches, the operation's input as its type writes
  it, and the capabilities it carries, each a COSE Sign1 as it was signed, none where absent. So a
  call is whole wherever it goes -- over HTTP, over a Worker's RPC, held in a queue and run later --
  and the model checks what it carries as it checks its input; an operation's input names no
  credential, and a call over HTTP names the operation its path does. **A call made by a
  certificate is signed**, where what is reached must know who asks, the issuer first: its body is
  then a COSE Sign1 whose payload is the call's CBOR, `typ` `monoflake:call:1`, under the key the
  certificate certifies, so the interface, the operation, the input and the capabilities are bound
  together and none is carried to another. Envelope generates the call with the components that
  make one.
- **A union is a field's value, its case named inside it**: a bucket's kind is
  `{"name": "packed", "compress": true}`, so a field belongs to its case alone. It is written as
  ReScript's `@tag` lays it out, so it crosses into ReScript unconverted.
- **An optional field's absence has one meaning, written beside it**: a bucket with no `bindable`
  is bindable by every app, and one with an empty list by none.
- **Key 0 is reserved**: a record's content holds its `description` there, every kind's, and a
  union its case. An enumeration is its name in JSON and its code in CBOR; an ordered one's codes
  start at 1, and custody's, 0 and 1, are no order.
- **A version is raised for anything but an optional field added to a record**: the check refuses
  to write a product whose type, reached from a record's content, changed otherwise while its
  version stayed.
- **A kind of record is named within its half**, decided by the author on 2026-10-20, as each
  footing's shell writes it: one name may be a kind of each half, one concept kept in both, as an
  extension, or two, as an organization, `model/graph/records.res`. **An id names a kind of its own
  record's half**, within one footing, which its control checks exists and guards; **one across
  halves is written `Across`**, as a member's account is the platform's, which its control can
  neither check nor guard. A type two halves share names its ids so, each read in the half of the
  record holding it. On the wire either is an integer, so naming its kind otherwise breaks no
  reader, and the check compares what is written.
- **A value unique among a kind's rows is that kind's key**, decided by the author on 2026-10-20:
  its content names each set of its fields unique, `unique`, which its footing keeps as a table's
  key, a field absent counting as one value, so a label, a username, a domain, a node of the tree
  and a mount are each unique and still a record of a generation, gone back to as any is.
- **A record's keys are the subset's, CWT's or another standard's**, decided by the author on
  2026-10-20: the subset's from 1, key 0 reserved; a claim set's CWT's, a claim registered by its
  number, RFC 8392, or one of the platform's own below -65536, b8f35; and a type a standard
  defines, as a `COSE_Key`, the labels its RFC registers. So a standard's structure is written in the
  subset whole, and the check holds each key to whose it is. **A set of names, each a bit**, is
  `Flags`: the integer of the bits set in CBOR, the names set in JSON, as WIT's `flags`, RFC vr5lw;
  a capability's rights are one. **An id of any kind of a half** is written `Across` with `*`, a
  capability's resource, and stands in a signed record alone.
- **What is compiled or signed is no record**: a grant, a certificate, a bundle, a capability and an
  account credential are each made from what is written, never written themselves, RFC v7v3w, and
  are declared apart, with the signed records' own claims.
- **A reader passes over a field it does not know**, decided by the author on 2026-10-19, as the
  rule above asks: an optional field added keeps its version, so a reader of that version meets
  it, and refusing it would break what the version promises. A sample written in `tests/` is held
  otherwise, a field it does not know taken as a mistake in writing it.
- **An integer is read by its value, never its text**, decided on 2026-10-20 as envelope's two
  halves were held to one reading: any JSON number that is exactly an integer within its shape's
  bounds is that integer, `5.0` and `1e2` among them, since a JavaScript reader cannot tell them
  from `5` and `100`; in CBOR an integer alone is one. **A 64-bit float is finite**: CBOR's NaN or
  infinity is refused as `malformed`, since JSON carries neither and a value has to read back the
  same from both.
- **Bytes are read in one text alone**, decided by the author on 2026-10-19: base64url, unpadded,
  its unused last bits zero, and any other -- base64's own alphabet, a padding, a bit set past the
  last byte -- refused as `rejected` for `malformed`, naming the text expected. A value has one text, as it has one
  CBOR, and a client's mistake shows on its first call, while tightening later would break what
  was let in. WIT's `list<u8>` is written so as well, RFC vr5lw.

**CBOR, COSE's `Sign1` and CWT are held to their standards' tests**, worked out with the author on
2026-10-19: each is small and public with its own tests, so an implementation is held to all of
them, whoever wrote it.

| Standard                                             | Held to                                                                                    |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| CBOR, RFC 8949, deterministic encoding by its 4.2    | its Appendix A's 82 items and Appendix F's items that are not well formed, `docs/lessons/` |
| COSE, RFC 9052's `Sign1`, Ed25519 by RFC 9864, b8f35 | `cose-wg/Examples`' sign1, EdDSA and CWT cases, and cases of the platform's own for -19    |
| CWT, RFC 8392                                        | its Appendix A                                                                             |

- **Rust's CBOR is minicbor**, worked out with the author on 2026-10-19, maintained, its 2.3.1 of
  2026-10-18: neither it nor ciborium promises deterministic encoding, so what the platform's own
  cases find decides whether it is patched, forked or built. **It is wrapped**, decided by the
  author on 2026-10-20 once codec's cases were run: it reads `f8 00`, which RFC 8949's Appendix F
  refuses, reports a head of one byte and one inline as one type, and reads a half only with its
  `half` feature, so `codec*` holds what it misses on top of it and leaves it as its authors keep it.
- **ReScript's CBOR is written to behave as the Rust side does**, decided by the author on
  2026-10-20 in place of cbor2 with its `cde` on, decided on 2026-10-19: cbor2 reads into
  JavaScript's own values, so a float of 1.0 comes back an integer and a tag a `Date`, losing what
  `codec*`'s value keeps. It is held to the same samples, `docs/code.md`.
- **Every test runs in CI**, so what is taken or built stays whole.
- **`codec*` is begun**, the first block written against its brief, 2026-10-20.
