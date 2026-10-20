/** What every interface answers alike, RFC vr5lw: an error, its failure and its reason. */
open Subset

/** The reasons every operation may fail for, none of which an operation declares again: a
 * credential missing or wrong, and bytes in any text but base64url unpadded, fhg6w. */
let common: array<reason> = [
  {name: "denied", failure: #rejected},
  {name: "malformed", failure: #rejected},
]

let types: array<declared> = [
  {
    name: "failure",
    def: Enum({choices: codes(["rejected", "unavailable", "unknown"]), ordered: false}),
    from: "49qyg",
  },
  // A reason is one its operation declares; a message is for a person, and nothing acts on it.
  {
    name: "error",
    def: Record([
      field("failure", 1, Type("failure")),
      field("reason", 2, Prim(#string)),
      optional("message", 3, Prim(#string)),
    ]),
    from: "vr5lw",
  },
]
