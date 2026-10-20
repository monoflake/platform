/** Every library the drafts name: a package of one language, used by every component of it that needs it, RFC fhg6w. */
type library = {
  what: string,
  /** The language it is written in, a component using only libraries of its own, RFC fhg6w. */
  language: [#rust | #rescript],
  /** Whether its output must agree between components, so its version goes into what it writes. */
  agrees: bool,
  uses: array<string>,
}

let libraries: dict<library> = dict{
  "compat*": {
    language: #rescript,
    what: "versions: a frozen core, and ranges, features and refusals on it, wnqvu",
    agrees: true,
    uses: [],
  },
  "capability*": {
    language: #rescript,
    what: "a capability and its chain to the root, checked, vuanj",
    agrees: false,
    uses: ["compat*"],
  },
  "vocabulary*": {
    language: #rescript,
    what: "capabilities by name, type and rule; declared, allowed, offered compared, 49qyg",
    agrees: false,
    uses: ["compat*"],
  },
  "placement*": {
    language: #rescript,
    what: "where anything is placed among what meets its needs, scored by rendezvous over each one's weight: a parcel among stores, a deployment among hosts, b8f35, vr5lw",
    agrees: true,
    uses: ["compat*"],
  },
  "layout*": {
    language: #rescript,
    what: "content cut by FastCDC into pieces, packed into parcels, parity, b8f35",
    agrees: true,
    uses: ["compat*"],
  },
  "keys*": {
    language: #rescript,
    what: "a scope's salt and key, derived from the masters and its id, b8f35",
    agrees: true,
    uses: ["compat*"],
  },
  "wit*": {
    language: #rescript,
    what: "an export's types, and a call checked against them, 49qyg",
    agrees: false,
    uses: ["compat*"],
  },
  "extensions*": {
    language: #rescript,
    what: "a control's extensions: each host's binding, its credentials, quota, levels and grace, the networks its hosts may use, the capacity lists sent to drivers, and what it leases, the same code in both controls, v7v3w",
    agrees: false,
    uses: ["compat*"],
  },
  "sqlite*": {what: "the engine a tablet runs", language: #rescript, agrees: false, uses: []},
}
