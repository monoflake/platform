/***
 * `Derive` held to `tests/keys/derived.json`, every value derived, the extended output and every
 * refusal.
 */
open Node
open Sample

let derived = "tests/keys/derived.json"

let cases = name => read(derived)->at(["derived", name])->array

let master = name => read(derived)->hexAt(["masters", name])

test("a scope's salt is derived from the salt master and its id", () =>
  cases("salt")->Array.forEach(item => {
    let message = JSON.stringify(item)
    deepEqual(
      Derive.salt(~master=master("salt"), ~scope=item->numberAt(["scope"])),
      Ok(item->hexAt(["salt"])),
      ~message,
    )
  })
)

test("a scope's key is derived from the encryption master and its id", () =>
  cases("key")->Array.forEach(item => {
    let message = JSON.stringify(item)
    deepEqual(
      Derive.key(~master=master("encryption"), ~scope=item->numberAt(["scope"])),
      Ok(item->hexAt(["key"])),
      ~message,
    )
  })
)

test("a journal's key is derived from its scope's key and its seed", () =>
  cases("journal")->Array.forEach(item => {
    let message = JSON.stringify(item)
    deepEqual(
      Derive.journal(~key=item->hexAt(["key"]), ~seed=item->hexAt(["seed"])),
      Ok(item->hexAt(["journal"])),
      ~message,
    )
  })
)

test("a parcel's key is derived from its scope's key and its seed", () =>
  cases("parcel")->Array.forEach(item => {
    let message = JSON.stringify(item)
    deepEqual(
      Derive.parcel(~key=item->hexAt(["key"]), ~seed=item->hexAt(["seed"])),
      Ok(item->hexAt(["parcel"])),
      ~message,
    )
  })
)

test("the gear table is the first 2,048 bytes derived from a scope's salt", () =>
  cases("gear")->Array.forEach(item => {
    let message = JSON.stringify(item)
    deepEqual(Derive.gear(~salt=item->hexAt(["salt"])), Ok(item->hexAt(["gear"])), ~message)
  })
)

test("a store's score is the first 8 bytes derived from the parcel, the store and k", () =>
  cases("score")->Array.forEach(item => {
    let message = JSON.stringify(item)
    deepEqual(
      Derive.score(
        ~parcel=item->hexAt(["parcel"]),
        ~store=item->numberAt(["store"]),
        ~k=item->numberAt(["k"])->Float.toInt,
      ),
      Ok(item->hexAt(["score"])),
      ~message,
    )
  })
)

test("a derivation's extended output is as long as asked", () =>
  cases("extended")->Array.forEach(item => {
    let message = JSON.stringify(item)
    let context = item->at(["context"])->string
    switch Context.all->Array.find(c => Context.text(c) == context) {
    | Some(c) =>
      deepEqual(
        Derive.derive(
          c,
          item->hexAt(["material"]),
          ~length=item->numberAt(["length"])->Float.toInt,
        ),
        item->hexAt(["derived"]),
        ~message,
      )
    | None => JsError.throwWithMessage(`${message}: no such context`)
    }
  })
)

test("every refusal names its first refused part", () =>
  read(derived)
  ->at(["refused"])
  ->array
  ->Array.forEach(item => {
    let message = JSON.stringify(item)
    let expected = Error(refused(item))
    switch item->at(["call"])->string {
    | "salt" =>
      deepEqual(
        Derive.salt(~master=item->hexAt(["master"]), ~scope=item->numberAt(["scope"])),
        expected,
        ~message,
      )
    | "key" =>
      deepEqual(
        Derive.key(~master=item->hexAt(["master"]), ~scope=item->numberAt(["scope"])),
        expected,
        ~message,
      )
    | "journal" =>
      deepEqual(
        Derive.journal(~key=item->hexAt(["key"]), ~seed=item->hexAt(["seed"])),
        expected,
        ~message,
      )
    | "parcel" =>
      deepEqual(
        Derive.parcel(~key=item->hexAt(["key"]), ~seed=item->hexAt(["seed"])),
        expected,
        ~message,
      )
    | "gear" => deepEqual(Derive.gear(~salt=item->hexAt(["salt"])), expected, ~message)
    | "score" =>
      deepEqual(
        Derive.score(
          ~parcel=item->hexAt(["parcel"]),
          ~store=item->numberAt(["store"]),
          ~k=item->numberAt(["k"])->Float.toInt,
        ),
        expected,
        ~message,
      )
    | "keyed" =>
      deepEqual(
        Hash.keyed(~salt=item->hexAt(["salt"]), item->hexAt(["content"])),
        expected,
        ~message,
      )
    | call => JsError.throwWithMessage(`${message}: no call ${call}`)
    }
  })
)
