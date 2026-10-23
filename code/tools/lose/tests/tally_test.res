/***
 * `Tally` held to counting a path's asks and measuring its longest silence.
 */
open Node

let asked = (began, ended, answer): Tally.asked => {began, ended, answer}

test("a path answering every time holds, its longest gap the longest between answers", () => {
  let t = Tally.tally(
    ~path="entry",
    ~from=0.,
    ~until=2000.,
    [asked(0., 100., Ok()), asked(500., 600., Ok()), asked(1000., 1700., Ok())],
  )
  deepEqual((t.asked, t.answered, t.failed, t.longest), (3, 3, 0, 1100.))
  ok(Tally.held(t))
})

test("a failure counts against the path, and the silence runs to the window's end", () => {
  let refused = Error("curl: (7) Failed to connect\n000")
  let t = Tally.tally(
    ~path="entry",
    ~from=0.,
    ~until=20000.,
    [asked(0., 100., Ok()), asked(500., 600., refused), asked(1000., 1100., refused)],
  )
  deepEqual((t.answered, t.failed, t.longest), (1, 2, 19900.))
  deepEqual(t.reasons, [("curl: (7) Failed to connect", 2)])
  ok(!Tally.held(t))
  ok(Tally.line(t)->String.includes("failed 2, longest gap 19.9s, 2 times curl: (7)"))
})

test("a path never asked does not hold", () => {
  ok(!Tally.held(Tally.tally(~path="tunnel", ~from=0., ~until=1., [])))
})

test("an ask ending past the window stretches it", () => {
  let t = Tally.tally(~path="tunnel", ~from=0., ~until=1000., [asked(900., 3000., Error("x"))])
  deepEqual(t.longest, 3000.)
})
