# Code

How code is written here, by the conversation or by a worker given one block's brief. The
workspace's rules hold first; this file adds the platform's. Worked out with the author on
2026-10-20: the model says what is to be built and is its acceptance, a worker builds one block
against it, and the whole is held by the conversation.

## A block is written alone, against what the model asks

- **A block is one directory of what the model asks code of**: a component or a library,
  `model/checks/layout/blocks.res`; a driver's are `monoflake/driver`'s, held by `tree.res`, RFC
  7ykg6. `mise run brief <package>` prints what it holds, read from the model; no brief is written
  by hand. A block depends on another of its own tree only where the model names it by its package,
  `blocks`, as a driver's program does its kinds.
- **Its interface is the model's**: a ReScript `.resi` beside the module it types, and Rust's
  crate root, `src/lib.rs`, or a binary's `src/main.rs`. The conversation writes it and the author reviews it before the block
  is begun; a worker implements it and never edits it, and reports one that seems wrong.
- **A crate's root is its interface, and every module beneath it private**, decided by the author
  on 2026-10-20: it holds the types, the traits a worker implements for them and the constants,
  and declares one private `mod` for each `.resi` the block's ReScript holds, so what the crate
  makes public is the model's alone, held by the compiler, and both languages' modules are named
  alike. Rust declares no signature without its body but a trait's, so a trait is what the
  compiler holds an implementation to. A worker splits a module into its own beneath it, as
  `cbor.rs` holds `cbor/decode.rs`, and asks for a module beside it.
- **A worker owns its block's directory and nothing else.** `model/`, `tests/`, `vendor/`,
  `docs/`, the root's manifests and the interface are asked about, never changed; registering a
  block in the root's manifests is the conversation's.
- **`mise run accept <package> --from <revision>` is a block's whole acceptance**: its model half,
  `model/accept.res`, then `mise run built <package>`, its languages' build, formatting, lints and
  tests, in that order. It holds the block alone. The whole -- the graph, every contract, `mise run
  check` -- is the conversation's. A worker runs it without `--from`, and the conversation with it
  as it reads the diff, since a worker runs no jj: jj snapshots the one tree, and two snapshotting
  at once diverge, the workspace's `docs/delegation.md`.
- **A block builds alone, so one failing fails no other**, decided by the author on 2026-10-20.
  The root's `rescript.json` and `package.json` list no block, so `rescript build` at the root
  compiles the model alone, and each package is built by `rescript build <its directory>`, its own
  root, inheriting nothing: its `rescript.json` writes its output itself, `Blocks.rescriptOutput`.
  Cargo builds a crate alone already, by `-p`. Accept builds no model: the model is the
  conversation's, compiled before it dispatches, and two builds of one package at once collide on
  its lock.
- **A generated library's sources are its tool's, and the preparation writes them**, decided by
  the author on 2026-10-20, `model/graph/tools.res`. A tool is a block in `code/tools/`, its
  package named as the model names it, `envelope-generator`, since a library already holds the
  subject's name. Its Rust runs in the library's `build.rs`, which writes into cargo's `OUT_DIR`, so
  `cargo` alone builds it; its ReScript runs by `mise run generate`, which writes the library's
  `generated/`, ignored, before `built` builds it. `mise run prepare` makes a fresh clone ready:
  the packages installed, the model compiled, every generated library written. A crate's
  `build.rs` is the model's, as its root is, and what the generator writes is held to the
  library's interface and its samples.
- **A written block is in work or accepted**, `model/plan/work.res`, decided by the author on
  2026-10-20. The conversation marks it in work as it dispatches a worker or changes its interface,
  and accepted once accept passed and the diff was read. Whatever an accepted block fails -- its
  model half in `mise run check`, its build in `mise run blocks` -- fails verify; what one in work
  fails is listed in red after both and refuses no commit. Accept passes over changes inside
  another block in work, since workers share one tree; a change anywhere else outside the block is
  refused.
- **A package links the root's two licenses beside its manifests**, `LICENSE-MIT` and
  `LICENSE-APACHE`, each a link to the root's own, decided by the author on 2026-10-20: a package is
  read apart from its tree, by a registry or a reader, and carries its terms with it while the texts
  stay one.
- **A package's version is `0.0.0` while nothing is published**, decided by the author on
  2026-10-20, `Blocks.unpublished`: a version is a promise to whoever takes a release, and none is
  made yet. A block the model marks `released`, once the author opens its releases, keeps a
  version of its own from `0.1.0`, as `monoflake/driver`'s program will, RFC 8c0rg; until then
  every block of the author's own is `0.0.0`, a packaging of others' work keeping theirs.
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
- **A format of the platform's own is sampled by a reference apart from the code**, decided by
  the author on 2026-10-20: where no standard holds its vectors -- a cut, a parcel, a score -- the
  conversation computes them from the RFC's definition with other implementations of what it takes,
  in another language, and commits the data alone, the reference named in the file. Two
  implementations agreeing byte for byte is what says the definition was read one way; content too
  large to keep is given by a seed and held by its hash.
- **A test held back is a question, never a pass**: `#[ignore]`, a `todo` or a `skip` fails
  accept, so a block waiting on an answer is reported waiting rather than green.
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
  A test's own, `node:test` and `node:fs` among them, stand in `tests/bindings/`, since a library
  runs on the web's APIs alone and never node's.
- **Tests are `tests/`, run by `node --test`**, so no framework is taken for them; a package lists
  `tests` among its sources once it has one, as a `.resi` alone is passed over until its `.res` is
  written.

## Both in one block

- **A block's tests share one `tests/`**, decided by the author on 2026-10-20: cargo takes each
  `.rs` at its top as a test and passes over the rest, ReScript compiles the `.res` alone, and
  `node --test` runs what ReScript writes. One subject's tests stand side by side, `cbor.rs` beside
  `cbor_test.res`, the suffix keeping a test's module apart from the code's in ReScript's one space,
  so a language missing a subject shows.
- **What a maintained library gives, Rust takes, and ReScript follows it**, decided by the author on
  2026-10-20: a library kept by others is worth more than one written here, so the Rust side wraps
  it with what the platform asks beyond it and never edits it, `docs/vendor.md`; the ReScript side
  is written to behave as that does, held to the same samples. One that cannot be wrapped is asked
  about before it is forked.

## Rust

- **Every crate takes the root's lints**, `[lints] workspace = true`: `Blocks.rustLints` and
  `Blocks.clippyLints`, in the root's `[workspace.lints]`. No `unsafe`, every public item
  documented, and no `unwrap`, `expect`, `panic!`, indexing, `as` cast, wildcard over an enum, or
  `dbg!` in code; `clippy.toml` gives a test the ones a test asserts by.
- **A type says what a value may be**: an id is a newtype, a value within a range is made by a
  constructor that checks it, and an error is an enum of the reasons a caller acts on, RFC 49qyg's.
- **`todo!("<row>")`, never `unimplemented!`**, which the lints refuse.
