/***
 * What the runner counted for each contract, one entry for each interface, summed over every file
 * of it, and written as the JSON object the snapshot of RFC s42ex holds under `contracts`.
 */

/** One interface's cases as counted, each case once in each form. */
type counted = {passed: int, failed: int, waiting: int, skipped: int}

let none = {passed: 0, failed: 0, waiting: 0, skipped: 0}

/** Two counts added. */
let plus = (a, b) => {
  passed: a.passed + b.passed,
  failed: a.failed + b.failed,
  waiting: a.waiting + b.waiting,
  skipped: a.skipped + b.skipped,
}

/** A file's count added to the interface's, which is made by its first file. */
let add = (counts: dict<counted>, ~interface, counted) =>
  counts->Dict.set(interface, plus(counts->Dict.get(interface)->Option.getOr(none), counted))

let toJson = (counts: dict<counted>) => JSON.Object(
  counts->Dict.mapValues(c => JSON.Object(
    dict{
      "passed": JSON.Number(Int.toFloat(c.passed)),
      "failed": JSON.Number(Int.toFloat(c.failed)),
      "waiting": JSON.Number(Int.toFloat(c.waiting)),
      "skipped": JSON.Number(Int.toFloat(c.skipped)),
    },
  )),
)
