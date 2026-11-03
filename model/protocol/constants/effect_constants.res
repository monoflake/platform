/** The call bounds of model/protocol/calls.json scaled for TLC, as the author fixed them, 49qyg. */
@module("node:fs") external readText: (string, string) => string = "readFileSync"

exception Refused(string)

let bounds = () =>
  readText("model/protocol/calls.json", "utf8")
  ->JSON.parseOrThrow
  ->JSON.Decode.object
  ->Option.getOrThrow(~message="calls.json holds no object")

let value = (fields, name) =>
  fields
  ->Dict.get(name)
  ->Option.flatMap(JSON.Decode.float)
  ->Option.getOrThrow(~message=`calls.json lacks ${name}`)

// Ticks keep the bounds' order, not their seconds, which would swell the states past use: a lock's
// wait shorter than the lookup's deadline, and an id outliving the deadline, the wait and the hold.
let constants = () => {
  let fields = bounds()
  let wait = value(fields, "lockWait")
  let hold = value(fields, "lockHold")
  let deadline = value(fields, "lookupDeadline")
  let life = value(fields, "idLife")
  if !(wait > 0. && wait < deadline) {
    throw(Refused("calls.json's lockWait is not positive and below its lookupDeadline"))
  }
  if !(life > deadline +. wait +. hold) {
    throw(Refused("calls.json's idLife does not exceed lookupDeadline, lockWait and lockHold"))
  }
  dict{"Wait": 1, "Deadline": 2, "Life": 4}
}

Console.log(JSON.stringifyAny(constants())->Option.getOr("{}"))
