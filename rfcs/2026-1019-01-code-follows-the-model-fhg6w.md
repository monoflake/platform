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
  TypeScript, and is called by it, in one memory.
- **An edge between processes or hosts is a wire contract**, and only it.
- **A browser computes nothing of the platform's**: a page draws what its API returns, the
  workspace's `spec/code.md`, "A UI draws what an API gives". So what a server and a browser share is
  the contracts' types alone, generated, and no logic is written to run in both. Logic that parts of
  two languages both need is written in each and held to one set of cases kept beside it.
- **The rules the model checks of its graph are the code's rules of dependency** -- a `hard` edge
  points to its own layer or below, a library uses libraries alone -- so the check proves the code's
  boundaries where the code keeps the model's.

**Each language has its place**, worked out with the author on 2026-10-19:

| Language   | Where                                                                                                                                        |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Rust       | a part that runs natively on a machine: its driver, RFC vr5lw, and what needs speed, or memory that is predictable since nothing collects it |
| TypeScript | a part that runs as JavaScript, on a Worker or in `workerd` on a machine, what orchestrates among them; and the glue, tools and scripts      |
| ReScript   | a page's logic, where TypeScript's types are too loose; compiled to JavaScript and imported by TypeScript and Svelte                         |

- **OCaml is not written**, decided by the author on 2026-10-19. It was chosen so one library might
  run natively and, by Melange, in a browser; a browser computing nothing leaves that unasked, and
  what stays is a third native toolchain -- opam, dune's package management, which calls itself not
  final, Eio -- beside Rust's. ReScript keeps OCaml's types for a page and rides npm, `lessons.md`.
- **A part on a Worker is TypeScript, never Rust compiled to WebAssembly**: a Worker's ground is
  JavaScript, Rust there crosses into it by copying at every call and runs without tokio, and a
  machine's JavaScript part runs in `workerd`, so one bundle runs on both, vr5lw.
- **JavaScript, JSDoc and Svelte stand beside TypeScript** where a page or a tool asks. ReScript is
  never written inside a `.svelte` file, which it does not read; a page's logic is a `.res` module
  the page imports compiled.
- **ReScript's `int` is 32 bits**, so a 64-bit integer crossing into it, or into TypeScript, is a
  JavaScript `bigint`.
- **A TypeScript library runs on a Worker, in `workerd` and in a browser alike**, so it uses the
  web's standard APIs alone, never node's; I/O stands at a part's edge.
- **Each language's server is its own**: Rust's axum on tokio, TypeScript's Hono.
- **The tools are cargo, node, ReScript's compiler, vite and tsdown on rolldown, oxlint and oxfmt**,
  and TypeScript 6 and 7 side by side.

**A wire contract encodes as JSON for an API, and as CBOR for a record of the footing, a bundle and
a claim of a CWT**, in one shape a contract at a time, its CBOR deterministic by RFC 8949's 4.2.
**WIT stays the language of an app's exports**, RFC 49qyg: the platform's own contracts are written
in a language open below, WIT its users'.

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
  cases find decides whether it is patched, forked or built. TypeScript's is open beside the
  contracts' language [B28].
- **Every test runs in CI**, so what is taken or built stays whole.
- **None is begun yet**: this is the plan.

Open, for the discussion that follows:

- Which language each part of the model is written in, declared in the model beside the part, and
  the check that a part uses only libraries of its own language. [B24]
- How the repository is laid out, so cargo, ReScript's compiler and the JavaScript tools build one
  tree. [B26]
- Where ReScript ends and TypeScript begins on a page. [B27]
- The language a wire contract is written in, generated for Rust, TypeScript and ReScript, its JSON
  and CBOR alike; and TypeScript's CBOR. [B28]
