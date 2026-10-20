---
name: 'Code Follows the Model'
title: "The platform's code is cut where the model is: a component is a deployable in one language of three, a library a package of one language, and only an edge between processes is a wire contract"
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

How the platform's code is to be written, before any of it is: its languages, where one meets
another, and what crosses between them. Worked out with the author on 2026-10-19, on this project
alone, apart from the workspace's present rules and every other project; what changes in those when
this lands is for then.

The shape the discussion has reached so far:

**The model's boundaries are the code's**, since `model/graph/` already cuts the platform into
components, libraries and edges, each with its contract:

| In the model                              | In the code                                                              |
| ----------------------------------------- | ------------------------------------------------------------------------ |
| a component, `model/graph/components.res` | a deployable -- a process, a Worker, a binary -- written in one language |
| a library, `model/graph/libraries.res`    | a package of one language, used by every component of it that needs it   |
| an edge                                   | an interface between two components                                      |

- **An edge within one process is a call**, never serialized: ReScript compiled to JavaScript calls
  a library of JavaScript's, and is called by it, in one memory.
- **An edge between processes or hosts is a wire contract**, and only it.
- **A browser computes nothing of the platform's**: a page draws what its API returns. So what a
  server and a browser share is the contracts alone, generated, and no logic is written to run in
  both. Logic that components of
  two languages both need is written in each and held to one set of cases kept beside it.
- **The rules the model checks of its graph are the code's rules of dependency** -- a `hard` edge
  points to its own layer or below, a library uses libraries alone -- so the check proves the code's
  boundaries where the code keeps the model's.

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
- **ReScript's `int` is 32 bits**, so a 64-bit integer crossing into it, or into TypeScript, is a
  JavaScript `bigint`.
- **A library that runs as JavaScript runs on a Worker, in `workerd` and in a browser alike**, so it
  uses the web's standard APIs alone, never node's; I/O stands at a component's edge.
- **The tools are cargo, node, ReScript's compiler, vite and tsdown on rolldown, oxlint and oxfmt**,
  and TypeScript 6 and 7 side by side.

**The model and the code are one repository**, decided by the author on 2026-10-19, so the check
reads the code it holds to the model's boundaries, `model/contracts.json` reaches its generators
unpublished, and a change to both is one commit. Its top is five directories: `model/`, the spec;
`code/`; `docs/`, what is read; `scripts/`, the entries that drive the rest; and `vendor/`.

**A component's code is placed by its layer, in a directory named as the model names it**, worked out
with the author on 2026-10-19, so where code goes follows from the model and is never argued again:

| `code/`       | Layer | Holds                                                       |
| ------------- | ----- | ----------------------------------------------------------- |
| `apps/`       | 1     | the platform's own apps, the console; a user's are not here |
| `products/`   | 0     | the three products and the control that configures them     |
| `primitives/` | -1    | the five components the products are built from, RFC vuanj  |
| `substrate/`  | -2    | what those stand on: backings, the extent, hosts, drivers   |
| `platform/`   | -3    | the platform's half, which layer -3 is whole                |
| `libs/`       | --    | the libraries, placed by subject, a library having no layer |
| `tools/`      | --    | programs run while the platform is built: the generators    |

- **A half is never a directory**, since the layers already part them: layer -3 is the platform's
  half and every layer above it the organization's, so `control(organization)` is
  `products/control` and `control(platform)` `platform/control`.
- **A library's language is a property the model declares, never a directory.**
- **Each component declares its language in the model**, decided by the author on 2026-10-19, and
  the language follows from where it must run: ReScript for what must run on a Worker, which then
  runs in `workerd` on a machine alike, and Rust for what runs only natively on a machine. Since an
  organization's resources may be Cloudflare's, every component is ReScript; an app's code is its
  user's and the root runs nothing, so neither declares one. **Where the platform meets a vendor, a
  kind is a contract with an implementation a vendor**, and the language is the implementation's:
  a driver declares none, and lies as a directory of its implementations, `machine-driver`'s Rust
  and `cloudflare-driver`'s ReScript, RFC vr5lw. **The drivers lie together in `substrate/driver/`**,
  decided by the author on 2026-10-19, each named without the word its parent says,
  `driver/cloudflare` and `driver/machine`, as a half is dropped from a name.
  `model/checks/code.res` holds that each component's code lies in its layer's directory, named as
  the model names it, that its manifest is its language's, and that it uses only libraries of its
  own language.

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
| a signed 64-bit integer, a decimal string in JSON   | `i64`                      | `bigint`                   |

Left out: generics, functions, `null`, and whatever one language alone has, decided by the author
on 2026-10-19 with the four below, from the bucket's trial, `model/contracts/`. **An integer of 64
bits was left out until something asked one**: SQLite's does, so it came in with the database's
interface, decided by the author on 2026-10-19, written as a decimal string in JSON, which a
JavaScript number cannot hold exactly, and as an integer in CBOR.

**An interface is a set of operations in the subset**, decided by the author on 2026-10-19 with the
database's interface: each operation its input and its output, records declared, and the reasons it
may fail for, each a failure of RFC 49qyg's -- `rejected`, `unavailable` or `unknown` -- that a
caller acts on, the reason only told. An operation is reached at `POST /{interface}/{operation}`,
its input the body, its output or an `error` the answer, JSON or CBOR by the request; an
interface's version is raised as a record's is, and the check refuses an operation gone or a type
it reaches changed while the version stayed. **The platform's own interfaces are all of the
subset**, a kind's and the database's among them; WIT is an app's alone.

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
- **Bytes are read in one text alone**, decided by the author on 2026-10-19: base64url, unpadded,
  its unused last bits zero, and any other -- base64's own alphabet, a padding, a bit set past the
  last byte -- refused as `rejected`, naming the text expected. A value has one text, as it has one
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
  cases find decides whether it is patched, forked or built. **JavaScript's is cbor2, its `cde` on**,
  decided by the author on 2026-10-19: the Common Deterministic Encoding, RFC 8949's 4.2.1, the rule
  minicbor is held to, so the two write the same bytes, and it reaches for no module of node's,
  `docs/lessons/languages.md`; held to the same tests.
- **Every test runs in CI**, so what is taken or built stays whole.
- **None is begun yet**: this is the plan.

Open, for the discussion that follows:

- How the repository is laid out past what is drawn, so cargo, ReScript's compiler and the
  JavaScript tools build one tree. [B26]
