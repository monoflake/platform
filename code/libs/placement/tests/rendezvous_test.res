/***
 * `Rendezvous` held to `tests/placement/ranked.json`, every score, every ranking and every refusal.
 */
open Node
open Sample

let samples = "tests/placement/ranked.json"

let cases = name => read(samples)->at([name])->array

test("a store's score is the highest over k of its derivation, as an unsigned 64-bit integer", () =>
  cases("scores")->Array.forEach(item => {
    let message = JSON.stringify(item)
    deepEqual(
      Rendezvous.score(~parcel=item->hexAt(["parcel"]), item->at(["store"])->store),
      Ok(item->at(["score"])->string->BigInt.fromStringOrThrow),
      ~message,
    )
  })
)

test("stores are ranked by their score, the highest first and a tie to the lower id", () =>
  cases("ranked")->Array.forEach(item => {
    let message = JSON.stringify(item)
    deepEqual(
      Rendezvous.ranked(~parcel=item->hexAt(["parcel"]), item->storesAt(["stores"]))->Result.map(
        ranked => ranked->Array.map(store => store.id),
      ),
      Ok(item->at(["ranked"])->array->Array.map(number)),
      ~message,
    )
  })
)

test("every refusal is the first in the interface's order", () =>
  cases("refused")->Array.forEach(item => {
    let message = JSON.stringify(item)
    deepEqual(
      Rendezvous.ranked(~parcel=item->hexAt(["parcel"]), item->storesAt(["stores"])),
      Error(refused(item)),
      ~message,
    )
  })
)
