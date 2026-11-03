open Node

testAsync("stages list only what ran in order with seconds to one decimal", async () => {
  let clock = ref(1000.)
  let timing = Timing.make(~now=() => clock.contents, ())
  deepEqual(Timing.lines(timing), [])
  let result = Timing.run(timing, "the machine asked", () => {
    clock := 2250.
    Ok("facts")
  })
  deepEqual(result, Ok("facts"))
  let result = await Timing.runAsync(timing, "the live driver checked before", async () => {
    clock := 4250.
    Error("not reached")
  })
  deepEqual(result, Error("not reached"))
  Selection.snapshotted(Some("objects"), () =>
    Timing.run(timing, "the snapshot", () => true)
  )->ignore
  Timing.run(timing, "the run cleaned", () => clock := 4290.)
  deepEqual(
    Timing.lines(timing),
    [
      "conform: took 1.3s, the machine asked",
      "conform: took 2.0s, the live driver checked before",
      "conform: took 0.0s, the run cleaned",
    ],
  )
})
