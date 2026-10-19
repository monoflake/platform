---
name: 'Code Follows the Model'
title: "The platform's code is cut where the model is: a part is a deployable in one language, a library a package written once, and only an edge between processes is a wire contract, written in ATD"
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
this lands is for then. The aim is that business code is written once and runs wherever it is
needed, on a server natively and in a browser alike.

The shape the discussion has reached so far:

**The model's boundaries are the code's**, since `model/graph.ts` already cuts the platform into
parts, libraries and edges, each with its contract:

| In the model           | In the code                                                              |
| ---------------------- | ------------------------------------------------------------------------ |
| a part, `PARTS`        | a deployable -- a process, a Worker, a binary -- written in one language |
| a library, `LIBRARIES` | a package written once, used by every part that needs it                 |
| an edge                | an interface between two parts                                           |

- **An edge within one process is a call**, never serialized: OCaml compiled to JavaScript calls
  JavaScript, and is called by it, in one memory.
- **An edge between processes or hosts is a wire contract**, and only it.
- **What runs on a server and in a browser alike is a library**, written once in OCaml and compiled
  to each target, so it is never ported and never forks. So the rules the model checks of its graph
  -- a `hard` edge points to its own layer or below, a library uses libraries alone -- are the
  code's rules of dependency, and the check proves the code's boundaries where the code keeps the
  model's.

**Each language has its place:**

| Language   | Where                                                                                                            |
| ---------- | ---------------------------------------------------------------------------------------------------------------- |
| OCaml      | the main language: compiled natively, to JavaScript by Melange, or to WebAssembly, and faster to build than Rust |
| Rust       | what needs speed, or memory that is predictable since nothing collects it: a machine's driver, RFC vr5lw         |
| TypeScript | the glue, and JavaScript, JSDoc and Svelte beside it where a page or a tool asks                                 |

- **OCaml reaches JavaScript by Melange**, since it is made for applications whose other half is
  JavaScript: readable output, a module a file, at ease with npm and a bundler, `lessons.md`.
  Melange's `int` is 32 bits, so a 64-bit integer crossing into it is an `Int64`.
- **The tools are dune and cargo, node, vite and tsdown on rolldown, oxlint and oxfmt**, and
  TypeScript 6 and 7 side by side.
- **OCaml's compiler and libraries are locked by dune's package management**, worked out with the
  author on 2026-10-19: `dune pkg lock` writes the project's lock directory, kept in the
  repository, with the compiler among what it locks, so any machine builds the same as cargo and its
  lock do. opam is installed by mise, `github:ocaml/opam`, to search packages and to fall back on:
  dune calls its package management not final, `lessons.md`, and reads `.opam` files still, so a
  switch of opam's takes over should it fail. mise never manages the compiler, since a library is
  built for one compiler and lives in its switch or lock beside it.
- **OCaml's standard library is its own, `Stdlib`, alone**, worked out with the author on
  2026-10-19: Melange ships it, so it alone is sure on every target; Base and Core replace it,
  shadowing its modules and changing some of what they mean, and bring Jane Street's world with
  them; Containers extends it, and is taken only once a module of it is shown to build under
  Melange, `lessons.md`.
- **A library shared across targets is pure**: no I/O and no library of concurrency, since Eio does
  not run under Melange and JavaScript has its own; I/O stands at a part's edge alone, Eio on a
  server and a promise in a browser. This is what lets business code be written once.
- **An OCaml server is Eio and cohttp-eio, under a thin layer of the platform's own** shaped as
  axum's and Hono's are: a handler `Request.t -> Response.t` in direct style, a middleware
  `handler -> handler`, and a router, a few hundred lines. Dream, 1.0.0 since 2026-10-07, is nearer
  Hono out of its box, but stands on Lwt, whose promises spread through every signature that
  touches them, and brings sessions, forms and templates an API never asks. Rust's server is axum
  and TypeScript's Hono.

**A wire contract is written in ATD, for every language at once**: a type language shaped as
OCaml's types are -- records, sum types with payloads, options, defaults -- whose core is neutral
of format and takes annotations of any name, `lessons.md`.

- **Each language is generated from the one `.atd`**, never written by hand: OCaml and Melange by
  atdgen, TypeScript by atdts, and Rust by a backend the platform writes, emitting `serde` types,
  since ATD has none. Where a tool asks JSON Schema, `atdcat -jsonschema` exports it.
- **A contract encodes as JSON by atdgen's rules, and as CBOR by annotations of the platform's
  own**, `<cbor key="-65537">`, read by the OCaml and the Rust generators alike, so a record of the
  footing, a bundle and a claim of a CWT are written in ATD as an API's answer is.
- **The Rust backend is held to atdgen**: for each `.atd`, what atdgen writes is read by the Rust
  code and written again byte for byte, and the CBOR annotations are carried both ways between the
  two languages.
- **WIT stays the language of an app's exports**, RFC 49qyg: ATD is the platform's own contracts,
  WIT its users'.

**CBOR, COSE's `Sign1` and CWT are built by the platform, whole, to their standards**, worked out
with the author on 2026-10-19: each is small and public with its own tests, so a full
implementation is held to all of them, and the platform owns what its every record is written in.

| Built | Standard                                             | Held to                                                                                 |
| ----- | ---------------------------------------------------- | --------------------------------------------------------------------------------------- |
| CBOR  | RFC 8949, deterministic encoding by its 4.2 among it | its Appendix A's 82 items and Appendix F's items that are not well formed, `lessons.md` |
| COSE  | RFC 9052's `Sign1`, Ed25519 by RFC 9864, RFC b8f35   | `cose-wg/Examples`' sign1, EdDSA and CWT cases, and cases of the platform's own for -19 |
| CWT   | RFC 8392                                             | its Appendix A                                                                          |

- **Each is built twice**: in OCaml, one source for native and Melange, and in Rust, CBOR as a
  `serde` data format.
- **Every test runs in CI**, so what is built stays whole; what is general may be published for
  others, as a wheel built to a standard is.
- **None is begun yet**: this is the plan.

Open, for the discussion that follows:

- Which language each part of the model is written in, declared in the model beside the part. [B24]
- How the repository is laid out, so dune, cargo and the JavaScript tools build one tree, and how
  dune itself is installed. [B26]
- Whether the OCaml backend moves from atdgen to atdml, which ATD names as coming. [C33]
