open Node

test("all steps hold the deployed stamps and exactly the bytes written, in order", async () => {
  let (report, events, lines) = await Fake.run()
  equal(report, ({app: Some(42.), failed: None, notRun: []}: Steps.report))
  equal(
    events,
    [
      Fake.Deploy(None, "run-first", false),
      Ask(42., {method: "GET", path: "/", body: None}),
      Ask(42., {method: "PUT", path: "/row/reference", body: Some("row run\n")}),
      Ask(42., {method: "PUT", path: "/object/reference", body: Some("object run\n")}),
      Ask(42., {method: "GET", path: "/row/reference", body: None}),
      Ask(42., {method: "GET", path: "/object/reference", body: None}),
      Deploy(Some(42.), "run-second", false),
      Ask(42., {method: "GET", path: "/", body: None}),
      Ask(42., {method: "GET", path: "/row/reference", body: None}),
      Ask(42., {method: "GET", path: "/object/reference", body: None}),
    ],
  )
  equal(lines->Array.filter(line => line->String.includes(" passed,"))->Array.length, 9)
})

Steps.names->Array.forEachWithIndex((name, at) =>
  test(`a failure at ${name} stops before every later step`, async () => {
    let (report, events, lines) = await Fake.run(~fail=Some(name), ())
    equal(report.failed, Some(name))
    equal(report.notRun, Steps.names->Array.slice(~start=at + 1))
    equal(events->Array.length, at + 1 + (at > 6 ? 1 : 0))
    ok(lines->Array.some(line => line->String.includes(`${name} failed, status `)))
    if at < 8 {
      ok(lines->Array.some(line => line->String.includes("did not run")))
    }
    if at == 2 {
      ok(
        lines->Array.some(
          line =>
            line->String.includes("status 501") &&
              line->String.includes("no binding reaches database"),
        ),
      )
    }
  })
)

["answers", "row read back", "object read back", "row kept", "object kept"]->Array.forEach(name =>
  test(`${name} fails on different bytes even with HTTP 200`, async () => {
    let (report, _, _) = await Fake.run(~wrong=Some(name), ())
    equal(report.failed, Some(name))
  })
)

test("redeployed fails when the entry still answers the old stamp", async () => {
  let (report, events, _) = await Fake.run(~stale=true, ())
  equal(report.failed, Some("redeployed"))
  equal(report.notRun, ["row kept", "object kept"])
  equal(events->Array.length, 8)
})

test("redeployed refuses another app id", async () => {
  let (report, events, _) = await Fake.run(~otherApp=true, ())
  equal(report.failed, Some("redeployed"))
  equal(report.app, Some(42.))
  equal(events->Array.length, 7)
})

test("dry run invokes only deploy with its dry flag and draws no supplied id", async () => {
  let (report, events, _) = await Fake.run(~dry=true, ())
  equal(report.failed, None)
  equal(events, [Fake.Deploy(None, "run-first", true)])
})

test("every run starts with no supplied id and different payloads and stamps", async () => {
  let (_, first, _) = await Fake.run(~unique="first", ())
  let (_, second, _) = await Fake.run(~unique="second", ())
  equal(first->Array.get(0), Some(Fake.Deploy(None, "first-first", false)))
  equal(second->Array.get(0), Some(Fake.Deploy(None, "second-first", false)))
  ok(first->Array.get(2) != second->Array.get(2))
  ok(first->Array.get(3) != second->Array.get(3))
})
