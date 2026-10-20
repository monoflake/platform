/** Every library the drafts name: a package of one language, used by every component of it that needs it, RFC fhg6w. */
type library = {
  what: string,
  /** Whether its output must agree between components, so its version goes into what it writes. */
  agrees: bool,
  uses: array<string>,
}

let libraries: dict<library> = dict{
  "compat*": {
    what: "versions: a frozen core, and ranges, features and refusals on it, wnqvu",
    agrees: true,
    uses: [],
  },
  "capability*": {
    what: "a capability and its chain to the root, checked, vuanj",
    agrees: false,
    uses: ["compat*"],
  },
  "vocabulary*": {
    what: "capabilities by name, type and rule; declared, allowed, offered compared, 49qyg",
    agrees: false,
    uses: ["compat*"],
  },
  "placement*": {
    what: "where anything is placed among what meets its needs, scored by rendezvous over each one's weight: a parcel among stores, a deployment among hosts, b8f35, vr5lw",
    agrees: true,
    uses: ["compat*"],
  },
  "layout*": {
    what: "content cut by FastCDC into pieces, packed into parcels, parity, b8f35",
    agrees: true,
    uses: ["compat*"],
  },
  "keys*": {
    what: "a scope's salt and key, derived from the masters and its id, b8f35",
    agrees: true,
    uses: ["compat*"],
  },
  "wit*": {
    what: "an export's types, and a call checked against them, 49qyg",
    agrees: false,
    uses: ["compat*"],
  },
  "extensions*": {
    what: "a control's extensions: each host's binding, its credentials, quota, levels and grace, the networks its hosts may use, the capacity lists sent to drivers, and what it leases, the same code in both controls, v7v3w",
    agrees: false,
    uses: ["compat*"],
  },
  "sqlite*": {what: "the engine a tablet runs", agrees: false, uses: []},
}
