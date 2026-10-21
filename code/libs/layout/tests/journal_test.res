/***
 * `Journal` held to `tests/layout/journals.json`: every write sealed into its object, opened back,
 * the journal exported as the parcel it becomes, and every refusal, the first in the interface's
 * order.
 */
open Node
open Sample

let journals = "tests/layout/journals.json"

let key = read(journals)->hexAt(["key"])
let header = read(journals)->at(["header"])->Sample.header
let writes = read(journals)->at(["writes"])->array

let sealed = async (~key, ~header, ~first, pieces) =>
  switch await Journal.seal(~key, ~header, ~first, pieces) {
  | Ok(written) => written
  | Error(Key | Master | Seed | First | Empty | Overfull) =>
    JsError.throwWithMessage("a write unsealable")
  }

/** Every write's object, sealed in order. */
let objects = async () => {
  let objects = []
  for i in 0 to writes->Array.length - 1 {
    let write = writes->Array.getUnsafe(i)
    let written = await sealed(
      ~key,
      ~header,
      ~first=write->intAt(["first"]),
      content(write->at(["pieces"])),
    )
    objects->Array.push(written.object)
  }
  objects
}

/** A refusal a case names, as `Journal.unopened`. */
let unopened = (case): Journal.unopened =>
  switch refused(case) {
  | ("first", None) => First
  | ("prefix", None) => Prefix
  | ("reserved", None) => Reserved
  | ("revision", Some(revision)) => Revision(revision)
  | ("master", None) => Master
  | ("key", None) => Key
  | ("length", None) => Length
  | ("tag", Some(i)) => Tag(i)
  | (name, _) => JsError.throwWithMessage(`${name}: no such refusal`)
  }

/** A refusal a case names, as `Journal.unsealable`. */
let unsealable = (case): Journal.unsealable =>
  switch refused(case) {
  | ("key", None) => Key
  | ("master", None) => Master
  | ("seed", None) => Seed
  | ("first", None) => First
  | ("empty", None) => Empty
  | ("overfull", None) => Overfull
  | (name, _) => JsError.throwWithMessage(`${name}: no such refusal`)
  }

testAsync("each write is sealed into its object and opened back", async () => {
  for i in 0 to writes->Array.length - 1 {
    let write = writes->Array.getUnsafe(i)
    let message = JSON.stringify(write->at(["pieces"]))
    let first = write->intAt(["first"])
    let pieces = content(write->at(["pieces"]))
    let {object, next} = await sealed(~key, ~header, ~first, pieces)
    let head = write->hexAt(["head"])
    deepEqual(object->TypedArray.slice(~start=0, ~end=TypedArray.length(head)), head, ~message)
    deepEqual(TypedArray.length(object), write->intAt(["length"]), ~message)
    deepEqual(hashed(object), write->hexAt(["object"]), ~message)
    deepEqual(next, write->intAt(["next"]), ~message)
    deepEqual(await Journal.opened(~key, ~header, ~first, object), Ok((pieces, next)), ~message)
  }
})

testAsync(
  "a journal's first object says its master's version before its key is derived",
  async () => {
    let objects = await objects()
    deepEqual(objects->Array.get(0)->Option.map(Journal.begun), Some(Ok(header.master)))
  },
)

testAsync(
  "a journal exported is its objects opened in order and sealed as its parcel",
  async () => {
    let objects = await objects()
    let opened = []
    let first = ref(0)
    for i in 0 to objects->Array.length - 1 {
      switch await Journal.opened(
        ~key,
        ~header,
        ~first=first.contents,
        objects->Array.getUnsafe(i),
      ) {
      | Ok((bytes, next)) =>
        opened->Array.push(bytes)
        first := next
      | Error(_) => JsError.throwWithMessage(`object ${Int.toString(i)}: not opened`)
      }
    }
    let joined = Uint8Array.fromLength(
      opened->Array.reduce(0, (total, bytes) => total + TypedArray.length(bytes)),
    )
    let _ = opened->Array.reduce(0, (at, bytes) => {
      joined->Web.setFrom(bytes, at)
      at + TypedArray.length(bytes)
    })
    let exported = read(journals)->at(["exported"])
    switch await Parcel.seal(~key=exported->hexAt(["key"]), ~header, joined) {
    | Ok(parcel) => deepEqual(hashed(parcel), exported->hexAt(["sealed"]))
    | Error(_) => JsError.throwWithMessage("the journal not exported")
    }
  },
)

testAsync("what cannot be sealed is refused by the first reason", async () => {
  let items = read(journals)->at(["unsealable"])->array
  for i in 0 to items->Array.length - 1 {
    let item = items->Array.getUnsafe(i)
    deepEqual(
      await Journal.seal(
        ~key=item->hexAt(["key"]),
        ~header=item->at(["header"])->Sample.header,
        ~first=item->intAt(["first"]),
        Uint8Array.fromLength(item->intAt(["length"])),
      ),
      Error(unsealable(item)),
      ~message=JSON.stringify(item),
    )
  }
})

testAsync("what cannot be opened is refused by the first reason", async () => {
  let objects = await objects()
  let cases = read(journals)->at(["unopened", "cases"])->array
  for i in 0 to cases->Array.length - 1 {
    let case = cases->Array.getUnsafe(i)
    let message = JSON.stringify(case)
    let first = case->intAt(["first"])
    let key = case->member("key")->Option.mapOr(key, key => key->string->hex)
    // The first write's object where `first` is 0, and the second's where it is any other.
    let bytes = objects->Array.getUnsafe(first == 0 ? 0 : 1)->changed(case)
    deepEqual(
      (await Journal.opened(~key, ~header, ~first, bytes))->Result.map(_ => ()),
      Error(unopened(case)),
      ~message,
    )
    if first == 0 {
      // The prefix alone is asked of `begun`: a version of 0 refused, another than the header's
      // read as it is.
      let version = bytes->TypedArray.slice(~start=1, ~end=5)
      deepEqual(
        Journal.begun(bytes)->Result.map(_ => ()),
        switch unopened(case) {
        | (Prefix | Reserved | Revision(_)) as refused => Error(refused)
        | Master if version->TypedArray.every(byte => byte == 0) => Error(Master)
        | First | Master | Key | Length | Tag(_) => Ok()
        },
        ~message,
      )
    }
  }
})
