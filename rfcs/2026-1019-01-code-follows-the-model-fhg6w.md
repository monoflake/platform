---
name: 'Code Follows the Model'
title: "The platform's code is cut where the model is: a part is a deployable in one language of three, a library a package of one language, and only an edge between processes is a wire contract"
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

**The model's boundaries are the code's**, since `model/graph.ts` already cuts the platform into
parts, libraries and edges, each with its contract:

| In the model           | In the code                                                              |
| ---------------------- | ------------------------------------------------------------------------ |
| a part, `PARTS`        | a deployable -- a process, a Worker, a binary -- written in one language |
| a library, `LIBRARIES` | a package of one language, used by every part of it that needs it        |
| an edge                | an interface between two parts                                           |

- **An edge within one process is a call**, never serialized: ReScript compiled to JavaScript calls
  a library of JavaScript's, and is called by it, in one memory.
- **An edge between processes or hosts is a wire contract**, and only it.
- **A browser computes nothing of the platform's**: a page draws what its API returns. So what a
  server and a browser share is the contracts alone, generated, and no logic is written to run in
  both. Logic that parts of
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

- **A part on a machine is Rust whole, its orchestration among it**: its libraries are Rust already,
  and a build that keeps every library's compiled output in a cache rebuilds only the part, within
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
    writes `.d.ts` itself, `lessons.md`.
- **OCaml is not written**, decided by the author on 2026-10-19. It was chosen so one library might
  run natively and, by Melange, as JavaScript; a browser computing nothing leaves that unasked, and
  what stays is a third native toolchain -- opam, dune's package management, which calls itself not
  final, Eio -- beside Rust's. ReScript keeps OCaml's types where JavaScript runs and rides npm,
  `lessons.md`.
- **A part on a Worker is never Rust compiled to WebAssembly**: a Worker's ground is JavaScript,
  Rust there crosses into it by copying at every call and runs without tokio, and a machine's
  JavaScript part runs in `workerd`, so one bundle runs on both, vr5lw.
- **ReScript is never written inside a `.svelte` file**, which it does not read; a page's logic is a
  `.res` module the page imports compiled.
- **ReScript's `int` is 32 bits**, so a 64-bit integer crossing into it, or into TypeScript, is a
  JavaScript `bigint`.
- **A library that runs as JavaScript runs on a Worker, in `workerd` and in a browser alike**, so it
  uses the web's standard APIs alone, never node's; I/O stands at a part's edge.
- **The tools are cargo, node, ReScript's compiler, vite and tsdown on rolldown, oxlint and oxfmt**,
  and TypeScript 6 and 7 side by side.

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
- **The model writes one product, `contracts.json`**, committed: every contract in the subset below,
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
| an integer of 32 bits; of 64                        | `i32`; `i64`               | `int`; `bigint`            |
| bytes                                               | `Vec<u8>`                  | `Uint8Array.t`             |
| a record, a field absent when it has nothing to say | a struct, `Option` fields  | a record, optional fields  |
| a closed set of names                               | an enum without data       | a variant without payloads |
| a union tagged by a field, with payloads            | an enum, tagged internally | a variant under `@tag`     |
| a list; a map keyed by string                       | `Vec`; `BTreeMap`          | `array`; `dict`            |

Left out: generics, functions, `null`, and whatever one language alone has. A tagged union is
written as ReScript's `@tag` lays it out, so it crosses into ReScript unconverted.

**CBOR, COSE's `Sign1` and CWT are held to their standards' tests**, worked out with the author on
2026-10-19: each is small and public with its own tests, so an implementation is held to all of
them, whoever wrote it.

| Standard                                             | Held to                                                                                 |
| ---------------------------------------------------- | --------------------------------------------------------------------------------------- |
| CBOR, RFC 8949, deterministic encoding by its 4.2    | its Appendix A's 82 items and Appendix F's items that are not well formed, `lessons.md` |
| COSE, RFC 9052's `Sign1`, Ed25519 by RFC 9864, b8f35 | `cose-wg/Examples`' sign1, EdDSA and CWT cases, and cases of the platform's own for -19 |
| CWT, RFC 8392                                        | its Appendix A                                                                          |

- **Rust's CBOR is minicbor**, worked out with the author on 2026-10-19, maintained, its 2.3.1 of
  2026-10-18: neither it nor ciborium promises deterministic encoding, so what the platform's own
  cases find decides whether it is patched, forked or built. JavaScript's is open [B29].
- **Every test runs in CI**, so what is taken or built stays whole.
- **None is begun yet**: this is the plan.

Open, for the discussion that follows:

- Which language each part of the model is written in, declared in the model beside the part, and
  the check that a part uses only libraries of its own language. [B24]
- How the repository is laid out, so cargo, ReScript's compiler and the JavaScript tools build one
  tree. [B26]
- How bytes and a 64-bit integer are written in JSON, and which library is JavaScript's CBOR.
  [B29]
