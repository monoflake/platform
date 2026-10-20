# Languages

Facts on the languages, contracts and encodings the code is written in, each with its source; see `docs/lessons.md`.

## Contracts and their encodings, read 2026-10-19

**ATD is a language of types for data crossing languages**, its core neutral of format: "Types are
mapped to each programming language or data format using language-specific conventions", and it
takes annotations of any name. Its README lists atdcpp, atdd, atdj, atdgen for OCaml, "legacy", and
Melange, atdml for OCaml "coming soon", atdpy, atds and atdts, and no Rust; `atdcat -jsonschema`
exports JSON Schema. Its core reference is 651 lines; its tests are each backend's own, 82 files for
atdgen, 21 for atdts, 13 for atdpy, and no conformance suite. It is under BSD's three clauses.
Melange is served by atdgen's `-mel` and `melange-atdgen-codec-runtime`, 3.0.1 of 2025-03-17, work
Ahrefs funded. Asked by RFC fhg6w. Sources: https://github.com/ahrefs/atd,
https://atd.readthedocs.io/en/latest/atd-language.html,
https://ocaml.org/p/melange-atdgen-codec-runtime and
https://tech.ahrefs.com/getting-started-with-atd-and-melange-1f3a14004081

**Melange is OCaml's compiler for applications whose other half is JavaScript; js_of_ocaml for
reusing OCaml that exists.** OCaml.org gives Melange idiomatic output, deep integration with npm and
its tools, and "Excellent TypeScript interoperability", a module a file; js_of_ocaml compatibility
with most libraries and the standard library, OCaml 5's effects, limited support for domains, and
32-bit integers. Asked by fhg6w. Source: https://ocaml.org/tools/javascript-target

**CBOR is RFC 8949, 3674 lines of text, with its tests in it.** Its Appendix A has 81 encoded items,
64 of them as its 4.2.1 writes them; `cbor/test-vectors` keeps RFC 7049's 82 as JSON, one a simple
value RFC 8949 drops as not well formed, and states no license, so `tests/cbor/` is written from the
RFC's text instead. Its Appendix F lists about 90
byte sequences that are not well formed, by kind: input ending in a head, strings and containers
short of their items, reserved values, chunks of the wrong type, unclosed indefinite lengths. Its
4.2 defines deterministic encoding. Asked by fhg6w. Sources:
https://www.rfc-editor.org/rfc/rfc8949.txt and https://github.com/cbor/test-vectors

**minicbor 2.3.1 reads less strictly than RFC 8949 asks, read 2026-10-20 in its source**: its
`Decoder::simple` takes the byte after `0xf8` unchecked, so `f8 00`, not well formed by Appendix F,
is read; its `datatype` reports `0x00` to `0x18` alike as `U8`, so a head's width is told only by
`position()` before and after; and a half float is read only with its `half` feature. cbor2 reads
into JavaScript's own values unless told otherwise: 1.0 comes back the integer 1, tag 0 a `Date`,
tag 32 a `URL`. Asked by `codec*`. Sources: `minicbor-2.3.1/src/decode/decoder.rs` and the run
against `tests/cbor/`.

**COSE is RFC 9052, about 3600 lines, and CWT RFC 8392, 25 pages**; `cose-wg/Examples`, under the
Unlicense, holds 306 JSON cases, `sign1-tests`, `eddsa-examples` and `CWT` among them, written
before RFC 9864, so their EdDSA is -8. Asked by fhg6w. Sources:
https://www.rfc-editor.org/rfc/rfc9052.txt, https://www.rfc-editor.org/rfc/rfc8392.txt and
https://github.com/cose-wg/Examples

**OCaml today is opam 2.6.1, of 2026-10-07, OCaml 5.5.1, of 2026-09-04, and dune 3.24.2.** ocaml.org
installs it by opam, and warns that an opam from a system's package manager may be too old for the
newest compiler. A switch is "an isolated environment for the OCaml compiler and any packages you
install". Dune's own package management takes dependencies from `dune-project` into a lock file,
solved from nothing, with a relocatable compiler cached apart from the project; opam is kept beside
it. Asked by RFC fhg6w. Sources: https://ocaml.org/install,
https://dune.readthedocs.io/en/stable/explanation/package-management.html and
https://github.com/ocaml/opam/releases

**OCaml's servers, read 2026-10-19**: Dream 1.0.0, of 2026-10-07, after years of alphas and a new team
of maintainers from January 2026, MIT, on Lwt -- its handlers functions, its middleware composed by
`@@`, with sessions, CSRF, WebSockets, GraphQL, templates, TLS and HTTP/2 -- and a port to Eio under
way; cohttp-eio 6.3.0, a multicore HTTP/1.1 server in direct style on Eio, with no router or
middleware; httpun-eio 0.2.0, lower still; Vif 0.0.1~beta6 on Miou, "we do not recommend using this
project in production"; Piaf, a client. A 2026 account of OCaml web work in production uses Eio and
cohttp. Asked by fhg6w. Sources: https://github.com/camlworks/dream,
https://discuss.ocaml.org/t/the-new-owners-maintainers-of-dream/17712, https://ocaml.org/p/cohttp-eio,
https://github.com/robur-coop/vif and https://www.m3tech.blog/entry/2026/05/26/150000

**OCaml's libraries beside its own**: Base, "a complete and portable alternative" offering no I/O,
shadows the standard modules, and some of its functions differ, `List.map` tail-recursive in Base
and not in Stdlib; Core builds on it; Containers extends Stdlib rather than replacing it. Asked by
fhg6w. Sources: https://ocaml.org/p/base/latest and
https://discuss.ocaml.org/t/stdlib-vs-base-in-2025-beginner/16626

**Dune's package management is "not final yet and details are still subject to change"**, its
tutorial says. 3.24.0, of 2026-06-21, made the relocatable compiler its default, built once and
cached apart from a project, and locks developer tools, `dune fmt` using a locked ocamlformat;
3.25.0_alpha0 came on 2026-10-02. It installs the compiler and third-party packages by one tool from
opam's repositories, reading `.opam` files still; it installs no system package, sandboxes no build
as opam does by Bubblewrap, needs packages free of absolute paths, patching others in an overlay
repository, and solves from nothing. Open in its tracker: Windows, cross-compilation. mise's
registry holds opam, `github:ocaml/opam`, and no OCaml compiler or dune. Asked by RFC fhg6w. Sources:
https://dune.readthedocs.io/en/stable/tutorials/dune-package-management/index.html,
https://dune.readthedocs.io/en/stable/explanation/package-management.html and
https://github.com/ocaml/dune/releases

**Rust's CBOR crates, read 2026-10-19**: minicbor 2.3.1, of 2026-10-18, Blue Oak 1.0.0, no_std, with
`Encode` and `Decode` it derives and serde in `minicbor-serde`; ciborium 0.2.2, of 2024-01-24,
Apache-2.0, serde's, keeping a map's pairs in the order they came. Neither's documentation speaks of
deterministic encoding. OCaml's: cborl 0.1.0, AGPL, without half floats or indefinite strings; cbort,
ISC, on Zarith and bytesrw; cbor 0.4, RFC 7049's. Asked by RFC fhg6w. Sources:
https://docs.rs/minicbor/latest/minicbor/, https://github.com/enarx/ciborium, https://ocaml.org/p/cborl
and https://tangled.org/gazagnaire.org/ocaml-cbort

## The platform's languages after OCaml, read 2026-10-19

**ReScript is 12.3.1, of 2026-08-24**; 12.0.0, of 2025-11-25, brought a rewritten build system,
Rewatch, tracking dependencies across a monorepo's packages, with the old one kept as
`rescript-legacy`, and `@rescript/core` folded into the compiler as its standard library. 13 is
aimed at the fourth quarter of 2026, "release contents and timing may change": Rewatch alone, the
Ninja builder removed, source maps, ES modules by default, node 22 at least, and `.d.ts` files
generated by the compiler for the JavaScript it writes, so TypeScript reads a ReScript library with
no step beside it. Its `int` is 32 bits. Asked by RFC fhg6w. Sources:
https://rescript-lang.org/blog/release-12-0-0, https://en.wikipedia.org/wiki/ReScript,
https://rescript-lang.org/community/roadmap/ and
https://v11.rescript-lang.org/docs/manual/v11.0.0/primitive-types

**ReScript's own packages are few**: `rescript` counted between about 11,700 and 40,900 downloads a
week by sources that disagree, `@rescript/react` 5,776; it reaches npm's libraries by bindings. It
has no integration with Svelte: its team says a `.svelte` file imports the compiled JavaScript
instead, and a preprocessor for `<script lang="res">` exists only as a forum's sketch. Asked by
fhg6w. Sources: https://snyk.io/advisor/npm-package/rescript, https://depscope.dev/pkg/npm/rescript,
https://www.npmjs.com/package/@rescript/react,
https://rescript-lang.org/blog/what-can-i-do-with-rescript and
https://forum.rescript-lang.org/t/use-rescript-with-svelte/1762

**Rust on a Worker is `workers-rs`, the `worker` crate, 0.8.6**, built for
`wasm32-unknown-unknown`, with bindings for D1 and Durable Objects among others, and no tokio or
async-std. Asked by fhg6w. Sources: https://docs.rs/crate/worker/0.8.6 and
https://cdn.jsdelivr.net/gh/cloudflare/workers-rs@main/README.md

**ATD's tools are OCaml programs installed by opam**: `atdts` is not on npm, 404 on 2026-10-19, and
none of `atdts`, `atdgen` or `atdcat` is on this machine. atdgen's backend for BuckleScript,
ReScript's former name, is served by `atdgen-codec-runtime`, and no ReScript backend is named. Asked
by fhg6w. Sources: https://registry.npmjs.org/atdts,
https://opam-4.ocaml.org/packages/atdgen-codec-runtime/atdgen-codec-runtime.2.3.3 and
https://github.com/ahrefs/atd

**ReScript meets Workers and Hono by bindings the platform writes**: none named `rescript-hono` is
found, and `workers-res`, "Cloudflare Workers bindings for ReScript", is 0.0.3, a work in progress
with KV alone done. Hono's app is a fetch handler, so a binding wraps one function. Sury, formerly
`rescript-schema`, writes and reads JSON Schema, `S.toJSONSchema` and `S.fromJSONSchema`, its 11
in alpha. Asked by RFC fhg6w. Sources: https://npmjs.com/package/workers-res,
https://www.mintlify.com/honojs/hono/deployment/cloudflare-workers,
https://unpkg.com/sury@11.0.0-alpha.9/README.md and https://bestofjs.org/projects/sury

**ReScript's values are JavaScript's where they can be**: a record compiles to a plain object, an
array to an array, a string to a string, so they cross to TypeScript unconverted; a variant with a
payload compiles to an object tagged `TAG`, `{ TAG: "A"; _0: number }` in genType's TypeScript, and
genType exports ReScript's values and types to TypeScript and imports TypeScript's into ReScript.
Asked by RFC fhg6w. Sources: https://rescript-lang.org/docs/manual/latest/shared-data-types and
https://www.rescript-lang.org/docs/manual/typescript-integration

**JavaScript's CBOR, read 2026-10-19**: cbor2 2.4.0, of 2026-10-01, MIT, by hildjj, depends on
`@cto.af/wtf8` alone and imports no `node:` module; its encoder and decoder take `cde`, "all options
for draft-ietf-cbor-cde-05", and `dcbor`, with `rejectDuplicateKeys` and `sortKeys` apart. cbor-x
1.6.7, MIT, is fast and documents no deterministic encoding; its record extension, on by default,
changes how an object is written. Asked by RFC fhg6w. Sources: https://www.npmjs.com/package/cbor2,
https://github.com/hildjj/cbor2, the package's `lib/options.d.ts`, and
https://depscope.dev/pkg/npm/cbor-x
