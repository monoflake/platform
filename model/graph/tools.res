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
}

/** The tool writing a library's sources, by its name, if one does. */
let writerOf = library =>
  tools->Dict.toArray->Array.find(((_, t)) => t.writes == Some(library))->Option.map(((n, _)) => n)
