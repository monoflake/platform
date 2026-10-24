/***
 * `Counts` held to summing every file of one interface into one entry, and writing each
 * interface's four numbers by its name.
 */
open Node

test("the files of one interface are summed and another's kept apart", () => {
  let counts = Dict.make()
  counts->Counts.add(~interface="objects.write", {passed: 4, failed: 1, waiting: 2, skipped: 0})
  counts->Counts.add(~interface="management", {passed: 6, failed: 0, waiting: 0, skipped: 2})
  counts->Counts.add(~interface="objects.write", {passed: 2, failed: 0, waiting: 1, skipped: 3})
  deepEqual(
    counts->Dict.keysToArray->Array.toSorted(String.compare),
    ["management", "objects.write"],
  )
  deepEqual(
    counts->Dict.get("objects.write"),
    Some({Counts.passed: 6, failed: 1, waiting: 3, skipped: 3}),
  )
  deepEqual(
    counts->Dict.get("management"),
    Some({Counts.passed: 6, failed: 0, waiting: 0, skipped: 2}),
  )
})

test("the counts are written as an object from each interface to its four numbers", () => {
  let counts = Dict.make()
  counts->Counts.add(~interface="objects.write", {passed: 4, failed: 1, waiting: 2, skipped: 0})
  deepEqual(
    JSON.stringify(Counts.toJson(counts)),
    `{"objects.write":{"passed":4,"failed":1,"waiting":2,"skipped":0}}`,
  )
  deepEqual(JSON.stringify(Counts.toJson(Dict.make())), "{}")
})
