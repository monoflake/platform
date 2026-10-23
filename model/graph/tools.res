/**
 * Every tool, a program run while the platform is built and never deployed, in `code/tools/{name}`,
 * RFC fhg6w. A generator writes a library's sources from `model/contracts.json`.
 */
type tool = {
  what: string,
  languages: array<[#rust | #rescript]>,
  /** The platform's libraries it may depend on, by the model's names. */
  uses?: array<string>,
  /** Other tools it may depend on, by their names. */
  blocks?: array<string>,
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
  "deploy": {
    what: "a Worker's bundle, built by wrangler, packed as the function kind takes it and sent to a test machine as a list and a deployment, what a user runs to deploy an app of their own, n0o4l",
    languages: [#rescript],
    uses: ["envelope*"],
  },
  "conform": {
    what: "the kinds' samples run by the runner against the driver a test machine runs, on a second driver started from its binary with bindings of its own, the live one asked beside it and everything the run made removed after, n0o4l",
    languages: [#rescript],
    uses: ["envelope*"],
  },
  "lose": {
    what: "a test machine's driver stopped while hello is asked through its entry and its tunnel, its calls found refused, and the driver started again and found as it was, rmll5",
    languages: [#rescript],
    uses: ["envelope*"],
    blocks: ["conform"],
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
