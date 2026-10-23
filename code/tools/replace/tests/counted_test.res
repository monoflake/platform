/***
 * `Counted` held to counting an action's window apart, a refusal apart from a failure.
 */
open Node

let asked = (began, ended, outcome): Load.asked => {began, ended, outcome}

test("only the asks begun in the window count, and every one answered holds", () => {
  let asks = [
    asked(0., 100., Failed("before")),
    asked(1000., 1100., Answered),
    asked(1500., 1600., Answered),
    asked(2000., 2100., Failed("after")),
  ]
  let c = Counted.count(~path="entry", ~from=1000., ~until=2000., asks)
  deepEqual((c.made, c.answered, c.refused, c.failed), (2, 2, 0, 0))
  ok(Counted.held(c))
})

test("a refusal and a failure are counted apart, and both fail the window", () => {
  let asks = [
    asked(0., 50., Answered),
    asked(100., 110., Refused("connection refused")),
    asked(200., 210., Refused("connection refused")),
    asked(300., 900., Failed("HTTP 503")),
    asked(1000., 1050., Answered),
  ]
  let c = Counted.count(~path="tunnel", ~from=0., ~until=2000., asks)
  deepEqual((c.made, c.answered, c.refused, c.failed), (5, 2, 2, 1))
  deepEqual(c.longest, 1000.)
  deepEqual(c.reasons, [("refused, connection refused", 2), ("HTTP 503", 1)])
  ok(!Counted.held(c))
  ok(Counted.line(c)->String.includes("refused 2, failed 1, longest gap 1.0s"))
})

test("a window nothing was asked in does not hold", () => {
  ok(!Counted.held(Counted.count(~path="entry", ~from=0., ~until=1., [])))
})
