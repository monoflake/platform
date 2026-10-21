/**
 * Every tool, RFC fhg6w: a program run while the platform is built, never deployed, in
 * `code/tools/{name}`, each language's manifest beside the others' as a library's are. A generator
 * writes a library's sources from `model/contracts.json`: its Rust as the library's `build.rs`
 * runs it, into cargo's `OUT_DIR`; its ReScript as `mise run generate` runs its `src/main.res`,
 * given that file and the library's `generated/`, which is never committed. Decided by the author
 * on 2026-10-20.
 */
type tool = {
  what: string,
  languages: array<[#rust | #rescript]>,
  /** The platform's libraries it may depend on, by the model's names. */
  uses?: array<string>,
  /** The library whose sources it writes, by the model's name, if it is a generator. */
  writes?: string,
  takes?: array<Libraries.taken>,
  samples?: array<string>,
}

let tools: dict<tool> = dict{
  "envelope-generator": {
    what: "envelope*'s types, their JSON and CBOR and each interface's operations, written in each language from model/contracts.json, fhg6w",
    languages: [#rust, #rescript],
    writes: "envelope*",
    takes: [{language: #rust, name: "serde_json", major: "1"}],
  },
  "runner": {
    what: "the samples in tests/ run against an implementation: each case's calls made over HTTP as vr5lw writes them, each answer matched as expected, ge55b, p8e8k",
    languages: [#rescript],
    uses: ["envelope*", "codec*", "capability*"],
    takes: [
      {language: #rescript, name: "@noble/curves", major: "2"},
      {language: #rescript, name: "@noble/hashes", major: "2"},
    ],
  },
  "pins": {
    what: "the versions an image pins by hand, workerd's, moved to the newest released past the workspace's supply-chain delay, each with its download's hash, and a newer NixOS release named",
    languages: [#rescript],
  },
}

/** The tool writing a library's sources, by its name, if one does. */
let writerOf = library =>
  tools->Dict.toArray->Array.find(((_, t)) => t.writes == Some(library))->Option.map(((n, _)) => n)
