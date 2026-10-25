/*** `Ids` held to RFC b8f35, an app's id written as 8 hex digits, and one drawn on a machine. */
open Node
module Contracts = Envelope.Contracts

test("an id is 8 lowercase hex digits, leading zeros kept, and read back alone", () => {
  deepEqual(Ids.text(1.), "00000001")
  deepEqual(Ids.text(4275878552.), "fedcba98")
  deepEqual(Ids.ofText("0a1b2c3d"), Some(169552957.))
  deepEqual(Ids.ofText("ffffffff"), Some(4294967295.))
  deepEqual(
    ["2", "app-2", "0A1B2C3D", "a1b2c3d", "0a1b2c3d0", "00000000", " 0a1b2c3d"]->Array.map(
      Ids.ofText,
    ),
    [None, None, None, None, None, None, None],
  )
})

test("4 bytes are read big-endian, in the order the hex digits write them", () => {
  deepEqual(Ids.ofBytes(Uint8Array.fromArray([0x0a, 0x1b, 0x2c, 0x3d])), 169552957.)
  deepEqual(Ids.ofBytes(Uint8Array.fromArray([0xff, 0xff, 0xff, 0xff])), 4294967295.)
})

/** Draws given in turn. */
let scripted = draws => {
  let left = ref(draws)
  () =>
    switch left.contents {
    | list{next, ...rest} =>
      left := rest
      next
    | list{} => JsError.throwWithMessage("no draw left")
    }
}

test("a drawn id is checked, a held one and 0 drawn again, and a failed check stops it", () => {
  let asked = []
  let held = id => {
    asked->Array.push(id)
    Ok(id == 5.)
  }
  deepEqual(Ids.drawn(~random=scripted(list{5., 0., 7.}), ~held), Ok(7.))
  deepEqual(asked, [5., 7.])
  ok(Ids.drawn(~random=() => 5., ~held)->Result.isError)
  deepEqual(
    Ids.drawn(~random=() => 9., ~held=_ => Error("the machine did not answer")),
    Error("the machine did not answer"),
  )
})

test("the machine's list holds its items' ids and those of what it adopted", () => {
  let described: Contracts.ManagementDescribed.t = {
    generation: 1.,
    policy: 0.,
    grace: 0.,
    items: [{id: 3., capacity: Object({size: 1.}), state: Making}],
    adopted: [
      {kind: Function, name: "a", for_: Deployment({runs: App({id: 169552957.})})},
      {kind: Function, name: "b", for_: Item({id: 4.})},
    ],
  }
  deepEqual(Ids.listed(described), [3., 169552957., 4.])
})

test("a refusal names the app drawn for it first, and the retry redeploys that app", () => {
  deepEqual(Ids.named("app 0a1b2c3d, the host's driver did not answer"), Some(169552957.))
  deepEqual(
    [
      "the host's driver did not answer",
      "app 2, no",
      "app 0A1B2C3D, no",
      "an app 0a1b2c3d, no",
    ]->Array.map(Ids.named),
    [None, None, None, None],
  )
  deepEqual(
    Ids.retried(~given=None, ~drawn=Some(169552957.), "unreachable: gone"),
    "unreachable: gone; app 0a1b2c3d was opened, so deploy again with --app 0a1b2c3d to redeploy it",
  )
  deepEqual(Ids.retried(~given=Some(169552957.), ~drawn=Some(169552957.), "gone"), "gone")
  deepEqual(Ids.retried(~given=None, ~drawn=None, "gone"), "gone")
})
