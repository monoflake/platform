/**
 * Every library the drafts name, RFC fhg6w: one subject, in one language or several, each
 * language's manifest beside the others' in its one directory, `code/libs/{name}`, and used by
 * every component of any of them that needs it.
 */
/** A package of another project's a library may take, in one of its languages, at a major version. */
type taken = {language: [#rust | #rescript], name: string, major: string}

type library = {
  what: string,
  /**
   * The languages it is written in, a component using only a library written in its own, RFC fhg6w.
   */
  languages: array<[#rust | #rescript]>,
  /** Whether its output must agree between components, so its version goes into what it writes. */
  agrees: bool,
  uses: array<string>,
  /** What of others' it may take; a manifest taking anything else is refused, its brief says so. */
  takes?: array<taken>,
  /**
   * The samples it is held to, each a path under `tests/` or `vendor/`, which its own tests read in
   * every language it is written in.
   */
  samples?: array<string>,
}

let libraries: dict<library> = dict{
  "envelope*": {
    languages: [#rust, #rescript],
    what: "the contracts' types, their JSON and CBOR and each interface's operations, written from model/contracts.json by envelope-generator, fhg6w",
    agrees: true,
    uses: ["codec*"],
    takes: [{language: #rust, name: "serde_json", major: "1"}],
    samples: ["tests/codec"],
  },
  "codec*": {
    languages: [#rust, #rescript],
    what: "CBOR written deterministically by RFC 8949's 4.2.1 and read strictly, COSE's Sign1 by RFC 9052 and a CWT's claims by RFC 8392, the signature made and checked by what the caller gives, fhg6w",
    agrees: true,
    uses: [],
    takes: [
      {language: #rust, name: "minicbor", major: "2"},
      {language: #rust, name: "serde_json", major: "1"},
    ],
    samples: [
      "tests/cbor",
      "vendor/cose-examples/sign1-tests",
      "vendor/cose-examples/eddsa-examples/eddsa-sig-01.json",
      "vendor/cose-examples/eddsa-examples/eddsa-sig-02.json",
      "vendor/cose-examples/CWT/A_3.json",
    ],
  },
  "compat*": {
    languages: [#rust, #rescript],
    what: "versions: a frozen core, and ranges, features and refusals on it, wnqvu",
    agrees: true,
    uses: [],
    takes: [{language: #rust, name: "serde_json", major: "1"}],
    samples: ["tests/compat"],
  },
  "scope*": {
    languages: [#rescript],
    what: "a scope, a concept and never a process: its status and allowance read from its organization's bundle, and whether a need fits it, judged alike by every reader, vuanj",
    agrees: false,
    uses: ["vocabulary*", "compat*"],
  },
  "capability*": {
    languages: [#rescript],
    what: "a capability and its chain to the root, checked, vuanj",
    agrees: false,
    uses: ["compat*"],
  },
  "vocabulary*": {
    languages: [#rescript],
    what: "capabilities by name, type and rule; declared, allowed, offered compared, 49qyg",
    agrees: false,
    uses: ["compat*"],
  },
  "placement*": {
    languages: [#rescript],
    what: "where anything is placed among what meets its needs, scored by rendezvous over each one's weight: a parcel among stores, a deployment among hosts, b8f35, vr5lw",
    agrees: true,
    uses: ["compat*", "keys*"],
    samples: ["tests/placement"],
  },
  "layout*": {
    languages: [#rescript],
    what: "content cut by FastCDC into pieces, packed into parcels and sealed, a journal sealed write by write, parity waiting on C21, b8f35",
    agrees: true,
    uses: ["compat*", "keys*"],
    takes: [{language: #rescript, name: "@noble/hashes", major: "2"}],
    samples: ["tests/layout"],
  },
  "keys*": {
    languages: [#rescript],
    what: "every context derived under, and what is derived: a scope's salt and key from the masters and its id, a journal's and a parcel's key, the gear table, a store's score; and the BLAKE3 each record is named by, b8f35",
    agrees: true,
    uses: ["compat*"],
    takes: [{language: #rescript, name: "@noble/hashes", major: "2"}],
    samples: ["tests/keys"],
  },
  "wit*": {
    languages: [#rescript],
    what: "an export's types, and a call checked against them, 49qyg",
    agrees: false,
    uses: ["compat*"],
  },
  "extensions*": {
    languages: [#rescript],
    what: "a control's extensions: each host's binding, its credentials, quota, levels and grace, the networks its hosts may use, the capacity lists sent to drivers, and what it lends, the same code in both controls, v7v3w",
    agrees: false,
    uses: ["compat*"],
  },
  "sqlite*": {what: "the engine a tablet runs", languages: [#rescript], agrees: false, uses: []},
}
