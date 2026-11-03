/**
 * The compute product's interface for a call to an `effect`, RFC 49qyg: `status`, the one operation
 * taking a call's id, answering what became of the call from compute's records and the database's
 * own record of the call's batches, as the author decided on 2026-11-03.
 */
open Subset

let types: array<declared> = [
  // A call's id, 16 lowercase hex of a 64-bit integer, its high 48 bits milliseconds and its low 16
  // a sequence within the millisecond, issued by compute alone and never a function's input.
  {name: "call-id", def: Record([field("id", 1, Prim(#string))]), from: "49qyg"},
  {
    name: "call-outcome",
    def: Enum({choices: codes(["success", "rejected", "unavailable", "unknown"]), ordered: false}),
    from: "49qyg",
  },
  // The outcome told where one was, each step's sequence the stores committed, in order, when the
  // id expires, and whether the step marked last committed, as `call-steps` says it.
  {
    name: "call-status",
    def: Record([
      field("id", 1, Prim(#string)),
      optional("outcome", 2, Type("call-outcome")),
      field("committed", 3, List(Prim(#uint32))),
      field("expires", 4, Prim(#uint53)),
      field("finished", 5, Prim(#bool)),
    ]),
    from: "49qyg",
  },
  // What an `unknown` carries beside its error: the call's id, how long it was looked up in
  // milliseconds, and the sequence of the last step known committed, none where none was.
  {
    name: "call-unknown",
    def: Record([
      field("id", 1, Prim(#string)),
      field("looked", 2, Prim(#uint53)),
      optional("step", 3, Prim(#uint32)),
    ]),
    from: "49qyg",
  },
]

/** An id never issued or not yet recorded is `not_found`, one past its retention `forgotten`. */
let interface_: interface_ = {
  name: "compute",
  version: 1,
  from: "49qyg, vr5lw",
  operations: [
    op(
      "status",
      "call-id",
      "call-status",
      [("not_found", #rejected), ("forgotten", #rejected)],
      ~callers=[#capability],
    ),
  ],
}
