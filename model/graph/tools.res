/**
 * Every tool, a program run while the platform is built and never deployed, in `code/tools/{name}`,
 * RFC fhg6w. A generator writes a library's sources from `model/contracts.json`.
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
}

/** The tool writing a library's sources, by its name, if one does. */
let writerOf = library =>
  tools->Dict.toArray->Array.find(((_, t)) => t.writes == Some(library))->Option.map(((n, _)) => n)
