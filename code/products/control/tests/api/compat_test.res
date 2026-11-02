open Node
open Called

let range = (lowest, highest) => JSON.Object(
  dict{"lowest": JSON.Number(Int.toFloat(lowest)), "highest": JSON.Number(Int.toFloat(highest))},
)

let current = [
  ("management", Contracts.Interface.Management.version),
  ("deployments", Contracts.Interface.Deployments.version),
]

// Both interfaces at control's own range, or at the range given for each.
let versions = (~lowest=0, ~highest=0) =>
  current->Array.reduce(dict{}, (reported, (name, version)) => {
    reported->Dict.set(name, range(version + lowest, version + highest))
    reported
  })

let deploy = async stood => {
  let (binding, hash) = await opened(stood)
  await called(
    stood,
    Operator,
    releases(
      Deploy({binding, release: Envelope.Hex.decode(hash)->Option.getOr(Uint8Array.fromLength(0))}),
    ),
  )
}

let bindOrigin = async host => {
  let stood = stand(~direct=host.Host.reach.fetch)
  ignore(await called(stood, Operator, organizations(Open({label: "first"}))))
  let id = await openBinding(stood, 1.)
  let answer = await called(
    stood,
    Host(id),
    bindings(Bind({reach: Origin({origin: "https://driver.example.com"})})),
  )
  (stood, id, answer)
}

let accepts = (reported, ~driver) =>
  Compatibility.check(JSON.Object(dict{"versions": Object(reported)}), ~driver, ~warn=_ =>
    ok(false)
  )

test("overlapping ranges pass deployment and origin binding", async () => {
  let stood = stand()
  let reported = versions()
  // A name control does not know carries a range like the others, as a driver writes it.
  reported->Dict.set("future", range(7, 9))
  deepEqual(accepts(reported, ~driver="matching"), Ok())
  stood.host.versions := Some(JSON.Object(reported))
  let (status, _) = await deploy(stood)
  deepEqual(status, 200)
  ok(stood.host.deployed.contents->Option.isSome)
  let (_, _, (status, _)) = await bindOrigin(stood.host)
  deepEqual(status, 200)
})

test("a malformed value under any name is refused with a reason, never bound empty", async () => {
  let values = [JSON.String("not a range"), JSON.Number(3.), JSON.Null]
  let names = ["management", "future"]
  for i in 0 to names->Array.length - 1 {
    for j in 0 to values->Array.length - 1 {
      let reported = versions()
      reported->Dict.set(names->Array.getUnsafe(i), values->Array.getUnsafe(j))
      let stood = stand()
      stood.host.versions := Some(JSON.Object(reported))
      // The generated reader refuses the whole describe answer at the bad value, whichever name
      // holds it, so nothing is applied, deployed or bound.
      let (status, answer) = await deploy(stood)
      deepEqual(
        (status, (status, answer)->refusal),
        (
          503,
          (
            Some("unreachable"),
            "the host's driver answered what its type does not write, an object",
          ),
        ),
      )
      deepEqual(stood.host.deployed.contents, None)
      let (stood, id, (status, answer)) = await bindOrigin(stood.host)
      let (reason, _) = (status, answer)->refusal
      deepEqual((status, reason), (400, Some("not_proven")))
      deepEqual((await stood.parts.state.binding(id))->Option.flatMap(b => b.origin), None)
    }
  }
})

test("a roll in either order, and a rollback, overlap", async () => {
  // Same version, then a driver one behind and one ahead of control.
  let cases = [
    versions(),
    versions(~lowest=-1, ~highest=-1),
    versions(~lowest=-1, ~highest=0),
    versions(~lowest=0, ~highest=1),
    // A rollback, the driver newer and reading back to control's version.
    versions(~lowest=0, ~highest=2),
  ]
  cases->Array.forEachWithIndex((reported, at) =>
    deepEqual((at, accepts(reported, ~driver="rolling")), (at, Ok()))
  )
  let stood = stand()
  stood.host.versions := Some(JSON.Object(versions(~lowest=0, ~highest=1)))
  let (status, _) = await deploy(stood)
  deepEqual(status, 200)
})

test("ranges two or more apart refuse before deployment or origin binding", async () => {
  for i in 0 to current->Array.length - 1 {
    let (name, version) = current->Array.getUnsafe(i)
    let control = `${Int.toString(Math.Int.max(1, version - 1))} to ${Int.toString(version)}`
    // Control reads one behind its own, so a driver whose highest is two behind is apart, and one
    // whose lowest is two ahead.
    let outside = [(1, Math.Int.max(1, version - 2)), (version + 2, version + 3)]
    for j in 0 to outside->Array.length - 1 {
      let (lowest, highest) = outside->Array.getUnsafe(j)
      let reported = versions()
      reported->Dict.set(name, range(lowest, highest))
      let stood = stand()
      let draws = ref(0)
      let writes = ref(0)
      let state = stood.parts.state
      let stood = {
        ...stood,
        parts: {
          ...stood.parts,
          state: {
            ...state,
            drawApp: (~random) => {
              draws := draws.contents + 1
              state.drawApp(~random)
            },
            deploy: deployment => {
              writes := writes.contents + 1
              state.deploy(deployment)
            },
          },
        },
      }
      stood.host.versions := Some(JSON.Object(reported))
      let expected = `driver ${name} interface range ${Int.toString(lowest)} to ${Int.toString(
          highest,
        )} does not overlap control's range ${control}`

      // A driver below control's lowest only applies where control has a lowest above 1.
      if Math.Int.max(1, version - 1) > highest || lowest > version {
        let (status, answer) = await deploy(stood)
        deepEqual((status, (status, answer)->refusal), (400, (Some("invalid"), expected)))
        deepEqual((stood.host.applied.contents, stood.host.deployed.contents), (None, None))
        deepEqual((draws.contents, writes.contents), (0, 0))
        deepEqual(stood.host.seen->Array.length, 1)
        let (stood, id, (status, answer)) = await bindOrigin(stood.host)
        deepEqual((status, (status, answer)->refusal), (400, (Some("invalid"), expected)))
        deepEqual((await stood.parts.state.binding(id))->Option.flatMap(b => b.origin), None)
      }
    }
  }
})

test("an absent version report warns once per driver and passes", async () => {
  let warnings = []
  let warn = w => warnings->Array.push(w)
  let absent = JSON.Object(dict{})
  deepEqual(Compatibility.check(absent, ~driver="first", ~warn), Ok())
  deepEqual(Compatibility.check(absent, ~driver="first", ~warn), Ok())
  deepEqual(
    warnings,
    ["driver first reported no interface versions and was let through on first passage"],
  )
  deepEqual(Compatibility.check(absent, ~driver="second", ~warn), Ok())
  deepEqual(warnings->Array.length, 2)
  let stood = stand()
  let (status, _) = await deploy(stood)
  deepEqual(status, 200)
  let (_, _, (status, _)) = await bindOrigin(stood.host)
  deepEqual(status, 200)
})

test("only names control supports are read, and others pass whatever their value", async () => {
  let reported = versions()
  reported->Dict.set("future", JSON.String("not a number"))
  reported->Dict.set("other", JSON.Number(-1.5))
  deepEqual(
    Compatibility.check(
      JSON.Object(dict{"versions": Object(reported)}),
      ~driver="unknown",
      ~warn=_ => ok(false),
    ),
    Ok(),
  )
})

test("a report of only one of the two names is refused, whichever it is", async () => {
  let all = versions()
  ["management", "deployments"]->Array.forEach(name => {
    let reported = dict{}
    reported->Dict.set(name, all->Dict.get(name)->Option.getOr(JSON.Null))
    switch Compatibility.check(
      JSON.Object(dict{"versions": Object(reported)}),
      ~driver="partial",
      ~warn=_ => ok(false),
    ) {
    | Error(_) => ()
    | Ok() => ok(false)
    }
  })
})

test("malformed or incomplete reports refuse without a first passage warning", async () => {
  let reports = [
    JSON.Null,
    JSON.Array([]),
    JSON.Object(dict{}),
    JSON.Object(dict{"management": range(3, 2)}),
    JSON.Object(
      dict{"management": JSON.Object(dict{"lowest": JSON.Number(1.5), "highest": JSON.Number(3.)})},
    ),
    JSON.Object(dict{"management": Number(-1.)}),
    JSON.Object(dict{"management": Number(9007199254740992.)}),
    JSON.Object(dict{"management": String("3")}),
    JSON.Object(dict{"management": Number(Int.toFloat(Contracts.Interface.Management.version))}),
  ]
  let warnings = []
  reports->Array.forEach(versions =>
    switch Compatibility.check(
      JSON.Object(dict{"versions": versions}),
      ~driver="malformed",
      ~warn=w => warnings->Array.push(w),
    ) {
    | Error(_) => ()
    | Ok() => ok(false)
    }
  )
  deepEqual(warnings, [])
})
