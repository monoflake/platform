# Code

How code is written here, by the conversation or by a worker given one block's brief. The
workspace's rules hold first; this file adds the platform's. Worked out with the author on
2026-10-20: the model says what is to be built and is its acceptance, a worker builds one block
against it, and the whole is held by the conversation.

## A block is written alone, against what the model asks

- **A block is one directory of what the model asks code of**: a component, a driver's
  implementation of a kind or its management, or a library, `model/checks/layout/blocks.res`.
  `mise run brief <package>` prints what it holds, read from the model; no brief is written by hand.
- **Its interface is the model's**: a ReScript `.resi` beside the module it types, and Rust's
  `src/interface.rs`. The conversation writes it and the author reviews it before the block is
  begun; a worker implements it and never edits it, and reports one that seems wrong.
- **A worker owns its block's directory and nothing else.** `model/`, `tests/`, `vendor/`,
  `docs/`, the root's manifests and the interface are asked about, never changed; registering a
  block in the root's manifests is the conversation's.
- **`mise run accept <package> --from <revision>` is a block's whole acceptance**: its model half,
  `model/accept.res`, then its languages' formatting, lints and tests, in that order. It holds the
  block alone. The whole -- the graph, every contract, `mise run check` -- is the conversation's.
- **A block's tests read its samples as they stand**, each language the same files, the model's
  `samples`; a sample is never copied into a test, and accept refuses one no test of a language
  names, as it refuses an interface left unimplemented.
- **A block's tests hold its own structure, never what it takes on trust.** Codec holds that a
  signature's bytes go into a Sign1 and come out unchanged, and what is signed over is built byte for
  byte; whether a signature verifies is its signing library's, already tested by its authors.
  Running the real library through it is an end-to-end test, a further one, and never in place of
  the block's. Decided by the author on 2026-10-20.
- **A standard's own examples are taken from its text when nothing licensed holds them**: an RFC is
  public, so they are copied into `tests/` with the RFC and its section named in the file, as
  `tests/cbor/` is from RFC 8949. Decided by the author on 2026-10-20.
- **What is not decided waits behind a row**: `%todo("B32")` in ReScript, `todo!("B32")` in Rust,
  naming a row of the checklist still open. One naming no row, or a row closed, fails the check,
  so closing a row lists the code that waited on it.

## ReScript

- **ReScript 12 and its Stdlib alone**: no `Js.*`, no `Belt`, no `@rescript/core`; `throw`,
  `JsExn` and the `OrThrow` names, as https://rescript-lang.org/llms.txt documents them.
- **Warning 4 is on, and every warning is an error but 110**, a `%todo`: `Blocks.rescriptWarnings`,
  in each package's `rescript.json`, since ReScript inherits none. A match lists its variant's
  cases, because a wildcard over a variant of the platform's would hide a case added later, and
  finding every place a change reaches is what a sound type system is taken for.
- **JSON is read through `JSON.Decode`**, never by a match on its cases: JSON is no variant of the
  platform's, and a wildcard over it trips warning 4 for nothing. A transformation that must see
  every case lists them.
- **An invariant is a type**: abstract or `private`, made by the one function that checks it.
- **`%raw`, `Obj.magic` and `external` stand in `src/bindings/` alone**, as Rust's `unsafe` would,
  RFC fhg6w: one module a library bound, so what is taken on trust is gathered where it is seen.
  A test's own, `node:test` and `node:fs` among them, stand in `test/bindings/`, since a library
  runs on the web's APIs alone and never node's.
- **Tests are `test/`, run by `node --test`**, so no framework is taken for them; a package lists
  `test` among its sources once it has one, as a `.resi` alone is passed over until its `.res` is
  written.

## Rust

- **Every crate takes the root's lints**, `[lints] workspace = true`: `Blocks.rustLints` and
  `Blocks.clippyLints`, in the root's `[workspace.lints]`. No `unsafe`, every public item
  documented, and no `unwrap`, `expect`, `panic!`, indexing, `as` cast, wildcard over an enum, or
  `dbg!` in code; `clippy.toml` gives a test the ones a test asserts by.
- **A type says what a value may be**: an id is a newtype, a value within a range is made by a
  constructor that checks it, and an error is an enum of the reasons a caller acts on, RFC 49qyg's.
- **`todo!("<row>")`, never `unimplemented!`**, which the lints refuse.
