/*** The store's call bounds, model/protocol/calls.json, held to RFC 49qyg's order. */
open Testing

type url
@new external url: (string, string) => url = "URL"
@val external importMetaUrl: string = "import.meta.url"
@module("node:url") external pathOf: url => string = "fileURLToPath"
@module("node:fs") external readText: (string, string) => string = "readFileSync"

let bounds = () => {
  let path = pathOf(url("../../../../model/protocol/calls.json", importMetaUrl))
  let fields =
    JSON.parseOrThrow(readText(path, "utf8"))->JSON.Decode.object->Option.getOr(Dict.make())
  let value = name => fields->Dict.get(name)->Option.flatMap(JSON.Decode.float)->Option.getOr(-1.)
  (
    value("lockWait"),
    value("lockHold"),
    value("lookupDeadline"),
    value("idLife"),
    value("statusRetention"),
  )
}

test("are each a positive whole number of milliseconds", () => {
  let (wait, hold, lookup, life, retention) = bounds()
  [wait, hold, lookup, life, retention]->Array.forEach(value => {
    deepEqual(value > 0. && Math.floor(value) == value, true)
  })
})

test("give an id a life past the lookup, the lock wait and the hold together", () => {
  let (wait, hold, lookup, life, _) = bounds()
  deepEqual(life > lookup +. wait +. hold, true)
})

test("keep a call's status past the id's life", () => {
  let (_, _, _, life, retention) = bounds()
  deepEqual(retention > life, true)
})
