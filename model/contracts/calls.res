/** What every interface answers alike, RFC vr5lw: an error, its failure and its reason. */
open Subset

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
