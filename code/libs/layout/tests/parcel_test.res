/***
 * `Parcel` held to `tests/layout/parcels.json`: every parcel sealed, its head and its BLAKE3, opened
 * back to its capacity, where each piece fits, and every refusal, the first in the interface's order.
 */
open Node
open Sample

let parcels = "tests/layout/parcels.json"

let key = read(parcels)->hexAt(["key"])
let header = read(parcels)->at(["header"])->Sample.header

let sealed = async (~key, ~header, pieces) =>
  switch await Parcel.seal(~key, ~header, pieces) {
  | Ok(parcel) => parcel
  | Error(Key | Master | Seed | Overfull) => JsError.throwWithMessage("a parcel unsealable")
  }

/** A refusal a case names, as `Parcel.unopened`. */
let unopened = (case): Parcel.unopened =>
  switch refused(case) {
  | ("size", None) => Size
  | ("magic", None) => Magic
  | ("reserved", None) => Reserved
  | ("revision", Some(revision)) => Revision(revision)
  | ("master", None) => Master
  | ("key", None) => Key
  | ("tag", Some(i)) => Tag(i)
  | (name, _) => JsError.throwWithMessage(`${name}: no such refusal`)
  }

/** A refusal a case names, as `Parcel.unsealable`. */
let unsealable = (case): Parcel.unsealable =>
  switch refused(case) {
  | ("key", None) => Key
  | ("master", None) => Master
  | ("seed", None) => Seed
  | ("overfull", None) => Overfull
  | (name, _) => JsError.throwWithMessage(`${name}: no such refusal`)
  }

testAsync("pieces are sealed into a parcel and opened back, zeros after them", async () => {
  let items = read(parcels)->at(["sealed"])->array
  for i in 0 to items->Array.length - 1 {
    let item = items->Array.getUnsafe(i)
    let message = JSON.stringify(item->at(["pieces"]))
    let pieces = content(item->at(["pieces"]))
    let parcel = await sealed(~key, ~header, pieces)
    deepEqual(TypedArray.length(parcel), Parcel.size, ~message)
    deepEqual(parcel->TypedArray.slice(~start=0, ~end=64), item->hexAt(["head"]), ~message)
    deepEqual(hashed(parcel), item->hexAt(["sealed"]), ~message)
    deepEqual(Parcel.header(parcel), Ok(header), ~message)
    switch await Parcel.opened(~key, parcel) {
    | Ok((read, opened)) =>
      deepEqual(read, header, ~message)
      deepEqual(TypedArray.length(opened), Parcel.capacity, ~message)
      deepEqual(hashed(opened), item->hexAt(["opened"]), ~message)
      deepEqual(
        opened->TypedArray.slice(~start=0, ~end=TypedArray.length(pieces)),
        pieces,
        ~message,
      )
    | Error(_) => JsError.throwWithMessage(`${message}: not opened`)
    }
  }
})

test("a piece fits where the parcel has room for it whole, or nowhere", () =>
  read(parcels)
  ->at(["fits"])
  ->array
  ->Array.forEach(item =>
    deepEqual(
      Parcel.fits(~used=item->intAt(["used"]), ~length=item->intAt(["length"])),
      item->member("at")->Option.map(at => at->number->Float.toInt),
      ~message=JSON.stringify(item),
    )
  )
)

testAsync("what cannot be sealed is refused by the first reason", async () => {
  let items = read(parcels)->at(["unsealable"])->array
  for i in 0 to items->Array.length - 1 {
    let item = items->Array.getUnsafe(i)
    deepEqual(
      await Parcel.seal(
        ~key=item->hexAt(["key"]),
        ~header=item->at(["header"])->Sample.header,
        Uint8Array.fromLength(item->intAt(["length"])),
      ),
      Error(unsealable(item)),
      ~message=JSON.stringify(item),
    )
  }
})

testAsync(
  "what cannot be opened is refused by the first reason, its header read before",
  async () => {
    // The parcel the cases change, sealed of the sample's 1,000 bytes of pieces.
    let item = switch read(parcels)
    ->at(["sealed"])
    ->array
    ->Array.find(item => item->intAt(["pieces", "length"]) == 1000) {
    | Some(item) => item
    | None => JsError.throwWithMessage(`${parcels}: no parcel of 1000 bytes`)
    }
    let parcel = await sealed(~key, ~header, content(item->at(["pieces"])))
    let cases = read(parcels)->at(["unopened", "cases"])->array
    for i in 0 to cases->Array.length - 1 {
      let case = cases->Array.getUnsafe(i)
      let message = JSON.stringify(case)
      let bytes = parcel->changed(case)
      let key = case->member("key")->Option.mapOr(key, key => key->string->hex)
      let expected = unopened(case)
      deepEqual((await Parcel.opened(~key, bytes))->Result.map(_ => ()), Error(expected), ~message)
      deepEqual(
        Parcel.header(bytes)->Result.map(_ => ()),
        switch expected {
        | Key | Tag(_) => Ok()
        | Size | Magic | Reserved | Revision(_) | Master => Error(expected)
        },
        ~message,
      )
    }
  },
)
