/** What every interface answers alike, RFC vr5lw: an error, its failure and its reason. */
open Subset

/** The reasons every operation may fail for, none of which an operation declares again: a
 * credential missing or wrong; an input that does not parse, bytes in any text but base64url
 * unpadded among them, fhg6w; and an implementation overloaded for a moment, worth a retry. */
let common: array<reason> = [
  {name: "denied", failure: #rejected},
  {name: "malformed", failure: #rejected},
  {name: "overloaded", failure: #unavailable},
]

/** The reasons a call to what is deployed may fail for, beside every operation's: the platform's
 * own, answered as an `error` before the app's code is reached, vr5lw. What the app answers is its
 * own exports' in WIT, never these. */
let calling: array<reason> = [{name: "stopped", failure: #unavailable}]

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
