/*** The state a snapshot's counts give, by RFC s42ex's table, and a snapshot read from JSON. */
open Testing

let counts = (passed, failed, waiting, skipped): Snapshots.counted => {
  passed,
  failed,
  waiting,
  skipped,
}

test("each count gives its state", () =>
  deepEqual(
    [
      counts(0, 0, 0, 0),
      counts(0, 0, 4, 0),
      counts(3, 1, 2, 0),
      counts(3, 0, 2, 0),
      counts(5, 0, 0, 0),
      counts(5, 0, 0, 1),
      counts(0, 0, 0, 2),
    ]->Array.map(Measured.stateOf),
    [Measured.NoSamples, NotStarted, Failing, Thin, Whole, Thin, NotStarted],
  )
)

test("a snapshot is decoded and its contracts reported unbound", () => {
  let snapshot = Measured.decode(
    JSON.parseOrThrow(`{"target": "root@machine.example", "checkout": "abc", "at": "2026-10-24T00:00:00Z",
      "contracts": {"object": {"passed": 2, "failed": 0, "waiting": 0, "skipped": 0}}}`),
  )
  deepEqual(
    Measured.lines("root@machine.example", snapshot),
    [
      "root@machine.example: checkout abc at 2026-10-24T00:00:00Z, unbound",
      "root@machine.example object: whole, unbound, 2 passed, 0 failed, 0 waiting, 0 skipped",
    ],
  )
})

test("a snapshot with a count missing is unreadable, so unknown", () => {
  let snapshot = Measured.decode(
    JSON.parseOrThrow(`{"target": "t", "checkout": "abc", "at": "now",
      "contracts": {"object": {"passed": 2}}}`),
  )
  deepEqual(snapshot, None)
  deepEqual(Measured.lines("t", snapshot), ["t: unknown, no readable snapshot"])
})
