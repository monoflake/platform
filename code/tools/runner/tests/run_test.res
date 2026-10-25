/***
 * `Run.file` held to RFC p8e8k against a target in memory, its outcomes, `within`'s retries and
 * `wait` by the target's clock.
 */
open Node

let parse = JSON.parseOrThrow

/** An object store in memory, its clock held, a read of `late` found from `ready` on. */
let fake = (~ready=Float.Constants.positiveInfinity) => {
  let objects = Dict.make()
  let clock = ref(0.)
  let waits = []
  let calls = []
  let call = async (~interface as _, ~operation, ~input, ~form, ~as_ as _, ~bearer as _) => {
    calls->Array.push((operation, form))
    let name =
      input
      ->JSON.Decode.object
      ->Option.flatMap(o => o->Dict.get("name"))
      ->Option.flatMap(JSON.Decode.string)
    let notFound: Run.answered = Failed({failure: "rejected", reason: "not_found", message: "gone"})
    switch (operation, name) {
    | ("write", Some(name)) =>
      objects->Dict.set(
        name,
        input
        ->JSON.Decode.object
        ->Option.flatMap(o => o->Dict.get("content"))
        ->Option.getOr(JSON.Null),
      )
      Ok(Run.Answered(JSON.Object(dict{})))
    | ("read", Some("late")) =>
      Ok(
        clock.contents >= ready
          ? Run.Answered(parse(`{"content": "aGVsbG8", "size": 5}`))
          : notFound,
      )
    | ("read", Some(name)) =>
      switch objects->Dict.get(name) {
      | Some(content) =>
        Ok(Run.Answered(JSON.Object(dict{"content": content, "size": JSON.Number(5.)})))
      | None => Ok(notFound)
      }
    | _ => Error(`no ${operation}`)
    }
  }
  let target: Run.target = {
    call,
    send: async (~to as _, ~export as _, ~key as _, ~body, ~form as _) => Ok(
      Run.Answered(body->Option.getOr(JSON.Null)),
    ),
    given: async (~interface as _, ~form as _, given) =>
      given == None ? Ok() : Error(Filling.Unoffered("a case's given")),
    lose: async _ => Error(Filling.Unoffered("losing copies")),
    bound: _ => None,
    fixture: _ => Error("built from its source"),
    signed: (_, _) => Error("nothing signed"),
    now: () => clock.contents,
    wait: async ms => {
      waits->Array.push(ms)
      clock := clock.contents +. Int.toFloat(ms)
    },
    network: false,
    tunnel: false,
    captured: dict{},
  }
  (target, waits, calls)
}

let fileOf = text =>
  switch Sample.read(text) {
  | Ok(file) => file
  | Error(why) => JsError.throwWithMessage(why)
  }

let one = cases => fileOf(`{"interface": "object", "cases": ${cases}}`)

testAsync("a case run in CBOR and then in JSON passes in each", async () => {
  let (target, _, calls) = fake()
  let results = await Run.file(
    one(`[{"description": "written is read", "steps": [
      {"call": "write", "input": {"name": "a", "content": "aGVsbG8"}, "expect": {"output": {}}},
      {"call": "read", "input": {"name": "a"}, "expect": {"output": {"content": "aGVsbG8"}}},
      {"call": "read", "input": {"name": "b"}, "expect": {"failure": "rejected", "reason": "not_found"}}
    ]}]`),
    target,
  )
  deepEqual(results, [{description: "written is read", outcomes: [(Cbor, Passed), (Json, Passed)]}])
  deepEqual(
    calls,
    [
      ("write", Run.Cbor),
      ("read", Cbor),
      ("read", Cbor),
      ("write", Json),
      ("read", Json),
      ("read", Json),
    ],
  )
})

testAsync("a case fails at the step not answered as expected, saying why", async () => {
  let (target, _, _) = fake()
  let results = await Run.file(
    one(`[{"description": "d", "steps": [
      {"call": "write", "input": {"name": "a", "content": "aGVsbG8"}, "expect": {"output": {}}},
      {"call": "read", "input": {"name": "a"}, "expect": {"output": {"size": 6}}},
      {"call": "read", "input": {"name": "a"}, "expect": {"output": {}}}
    ]}, {"description": "e", "steps": [
      {"call": "read", "input": {"name": "none"}, "expect": {"output": {}}}
    ]}, {"description": "f", "steps": [
      {"call": "write", "input": {"name": "a", "content": "aGVsbG8"}, "expect": {"failure": "rejected", "reason": "too_large"}}
    ]}, {"description": "g", "steps": [
      {"call": "read", "input": {"name": {"$use": "never"}}, "expect": {"output": {}}}
    ]}]`),
    target,
  )
  let failed = (why: Run.outcome) => [(Run.Cbor, why), (Json, why)]
  deepEqual(
    results,
    [
      {
        description: "d",
        outcomes: failed(Failed({step: 1, why: "at size, expected 6, answered 5"})),
      },
      {
        description: "e",
        outcomes: failed(
          Failed({step: 0, why: "expected an answer, answered rejected not_found (gone)"}),
        ),
      },
      {
        description: "f",
        outcomes: failed(Failed({step: 0, why: "expected rejected too_large, answered {}"})),
      },
      {
        description: "g",
        outcomes: failed(Failed({step: 0, why: `$use "never", captured by no step before`})),
      },
    ],
  )
})

testAsync("a case needing what the target offers not is skipped, never passed", async () => {
  let (target, _, calls) = fake()
  let results = await Run.file(
    one(`[{"description": "given", "given": {"size": 1}, "steps": [
      {"call": "read", "input": {"name": "a"}, "expect": {"output": {}}}
    ]}, {"description": "lost", "steps": [
      {"call": "write", "input": {"name": "a", "content": "aGVsbG8"}, "expect": {"output": {}}},
      {"lose": 1},
      {"call": "read", "input": {"name": "a"}, "expect": {"output": {}}}
    ]}, {"description": "bound", "steps": [
      {"call": "write", "input": {"name": "a", "content": {"$bytes": {"length": {"bound": "content", "plus": 1}}}}, "expect": {"output": {}}}
    ]}, {"description": "fixture", "steps": [
      {"call": "write", "fixture": "echo-modules", "expect": {"output": {}}}
    ]}]`),
    target,
  )
  let skipped = what => {
    let why = Run.Skipped(`${what}: not offered by this target, left for later by RFC p8e8k`)
    [(Run.Cbor, why), (Json, why)]
  }
  deepEqual(
    results,
    [
      {description: "given", outcomes: skipped("a case's given")},
      {description: "lost", outcomes: skipped("losing copies")},
      {
        description: "bound",
        outcomes: skipped("the bound content, which the run is given no value of"),
      },
      {
        description: "fixture",
        outcomes: skipped("the fixture echo-modules, built from its source"),
      },
    ],
  )
  // Nothing of a case given what the target cannot set up is called, and a case losing copies ran
  // to there.
  deepEqual(calls, [("write", Run.Cbor), ("write", Json)])
})

testAsync("within is retried after 100 ms, doubling, until it answers as expected", async () => {
  let (target, waits, calls) = fake(~ready=700.)
  let results = await Run.file(
    one(`[{"description": "late", "steps": [
      {"call": "read", "input": {"name": "late"}, "expect": {"output": {"size": 5}}, "within": 5000}
    ]}]`),
    target,
  )
  deepEqual(results->Array.map(r => r.outcomes), [[(Run.Cbor, Run.Passed), (Json, Passed)]])
  // Tried at 0, 100, 300 and 700; the clock is past ready for the JSON form at once.
  deepEqual(waits, [100, 200, 400])
  deepEqual(calls->Array.length, 5)
})

testAsync("within fails once its time is past, naming the last answer and the tries", async () => {
  let (target, waits, _) = fake()
  let results = await Run.file(
    one(`[{"description": "never", "steps": [
      {"call": "read", "input": {"name": "late"}, "expect": {"output": {}}, "within": 1000}
    ]}]`),
    target,
  )
  let why = "expected an answer, answered rejected not_found (gone), after 5 tries within 1000 ms"
  deepEqual(
    results->Array.map(r => r.outcomes),
    [[(Run.Cbor, Run.Failed({step: 0, why})), (Json, Failed({step: 0, why}))]],
  )
  // The last try is made at the time's end, never past it.
  deepEqual(waits, [100, 200, 400, 300, 100, 200, 400, 300])
})

testAsync("the doubling stops at 2 s, and a wait moves the clock the target holds", async () => {
  let (target, waits, _) = fake(~ready=12000.)
  let results = await Run.file(
    one(`[{"description": "slow", "steps": [
      {"wait": 50},
      {"call": "read", "input": {"name": "late"}, "expect": {"output": {}}, "within": 20000}
    ]}]`),
    target,
  )
  deepEqual(results->Array.map(r => r.outcomes), [[(Run.Cbor, Run.Passed), (Json, Passed)]])
  deepEqual(
    waits->Array.slice(~start=0, ~end=10),
    [50, 100, 200, 400, 800, 1600, 2000, 2000, 2000, 2000],
  )
})

testAsync("a send's to is made from what was captured, and its answer matched", async () => {
  let (target, _, _) = fake()
  let results = await Run.file(
    fileOf(`{"interface": "deployments", "cases": [{"description": "sent", "steps": [
      {"call": "write", "input": {"name": "a", "content": "aGVsbG8"}, "expect": {"output": {}}},
      {"send": {"to": "http://localhost:1", "export": "echo", "body": {"text": "hello"}}, "expect": {"answer": {"text": "hello"}}},
      {"send": {"to": {"$use": "none"}, "export": "echo"}, "expect": {"answer": {}}}
    ]}]}`),
    target,
  )
  deepEqual(
    results->Array.map(r => r.outcomes),
    [
      [
        (Run.Cbor, Run.Failed({step: 2, why: `$use "none", captured by no step before`})),
        (Json, Failed({step: 2, why: `$use "none", captured by no step before`})),
      ],
    ],
  )
})

testAsync(
  "a fixture's version, form and artifact are written where the step writes none",
  async () => {
    let (target, _, _) = fake()
    let inputs = []
    let target: Run.target = {
      ...target,
      call: async (
        ~interface as _,
        ~operation as _,
        ~input,
        ~form as _,
        ~as_ as _,
        ~bearer as _,
      ) => {
        inputs->Array.push(input)
        Ok(Run.Answered(JSON.Object(dict{})))
      },
      fixture: name =>
        name == "echo-image"
          ? Ok({
              form: "image",
              address: "file:///f/echo-image.tar",
              hash: "ab",
              architecture: Some("arm64"),
            })
          : Error("not built"),
    }
    let results = await Run.file(
      fileOf(`{"interface": "deployments", "cases": [{"description": "deployed", "steps": [
      {"call": "deploy", "fixture": "echo-image", "input": {"port": 8080, "version": "cd"}, "expect": {"output": {}}}
    ]}, {"description": "unbuilt", "steps": [
      {"call": "deploy", "fixture": "echo-component", "input": {}, "expect": {"output": {}}}
    ]}]}`),
      target,
    )
    deepEqual(
      inputs->Array.getUnsafe(0),
      JSON.parseOrThrow(`{"port": 8080, "version": "cd", "form": "image",
      "artifact": {"address": "file:///f/echo-image.tar", "hash": "ab", "architecture": "arm64"}}`),
    )
    deepEqual(
      results->Array.getUnsafe(1),
      {
        description: "unbuilt",
        outcomes: [
          (
            Cbor,
            Skipped(
              "the fixture echo-component, not built: not offered by this target, left for later by RFC p8e8k",
            ),
          ),
          (
            Json,
            Skipped(
              "the fixture echo-component, not built: not offered by this target, left for later by RFC p8e8k",
            ),
          ),
        ],
      },
    )
  },
)

/** A target answering `open` with a binding's token and keeping each call's bearer and input. */
let binder = (~network) => {
  let (target, _, _) = fake()
  let seen = []
  let target: Run.target = {
    ...target,
    call: async (~interface as _, ~operation, ~input, ~form as _, ~as_, ~bearer) => {
      seen->Array.push((operation, as_, bearer, input))
      Ok(
        Run.Answered(
          operation == "open"
            ? parse(`{"binding": 4, "secret": "c2VjcmV0"}`)
            : parse(`{"binding": 4, "reached": {"name": "tunnel", "address": "10.200.0.4"}}`),
        ),
      )
    },
    network,
    tunnel: false,
    captured: dict{"organization": JSON.Number(7.)},
  }
  (target, seen)
}

let bound = fileOf(`{"interface": "bindings", "cases": [{"description": "bound", "steps": [
  {"call": "open", "as": "operator", "input": {"organization": {"$use": "organization"}}, "expect": {"output": {"$capture": "opened"}}},
  {"call": "bind", "bearer": {"$use": "opened"}, "input": {"reach": {"name": "tunnel"}}, "expect": {"output": {"binding": 4}}}
]}]}`)

testAsync(
  "a step carries the token a whole capture of open forms, after the run's organization",
  async () => {
    let (target, seen) = binder(~network=false)
    let results = await Run.file(bound, target)
    deepEqual(results, [{description: "bound", outcomes: [(Cbor, Passed), (Json, Passed)]}])
    deepEqual(
      seen->Array.slice(~start=0, ~end=2),
      [
        ("open", Some("operator"), None, parse(`{"organization": 7}`)),
        ("bind", None, Some("4.c2VjcmV0"), parse(`{"reach": {"name": "tunnel"}}`)),
      ],
    )
  },
)

testAsync("a bearer captured by no step before, or no token, fails its step", async () => {
  let (target, _) = binder(~network=false)
  let file = fileOf(`{"interface": "bindings", "cases": [{"description": "unbound", "steps": [
    {"call": "open", "input": {}, "expect": {"output": {"secret": {"$capture": "secret"}}}},
    {"call": "bind", "bearer": {"$use": "secret"}, "input": {}, "expect": {"output": {}}}
  ]}, {"description": "uncaptured", "steps": [
    {"call": "bind", "bearer": {"$use": "never"}, "input": {}, "expect": {"output": {}}}
  ]}]}`)
  let results = await Run.file(file, target)
  deepEqual(
    results->Array.map(r => r.outcomes->Array.map(((_, o)) => o)->Array.get(0)),
    [
      Some(
        Failed({
          step: 1,
          why: `the bearer secret, captured as "c2VjcmV0" and no binding's token`,
        }),
      ),
      Some(Failed({step: 0, why: "the bearer never, captured by no step before"})),
    ],
  )
})

testAsync(
  "a case needing the network is skipped where the run has none, and run where it has",
  async () => {
    let file = fileOf(`{"interface": "bindings", "cases": [{"description": "far", "network": true, "steps": [
    {"call": "bind", "input": {}, "expect": {"output": {"binding": 4}}}
  ]}]}`)
    let (offline, unseen) = binder(~network=false)
    let (online, _) = binder(~network=true)
    let skipped = await Run.file(file, offline)
    let ran = await Run.file(file, online)
    deepEqual(
      skipped->Array.flatMap(r =>
        r.outcomes->Array.map(
          ((form, outcome)) =>
            switch outcome {
            | Skipped(why) => (form, why->String.includes("needs the network"))
            | Passed | Failed(_) => (form, false)
            },
        )
      ),
      [(Cbor, true), (Json, true)],
    )
    deepEqual(
      (unseen, ran),
      ([], [{description: "far", outcomes: [(Cbor, Passed), (Json, Passed)]}]),
    )
  },
)

testAsync(
  "a case binding by a tunnel is skipped unless the run binds one, and run where it does",
  async () => {
    let file = fileOf(`{"interface": "bindings", "cases": [{"description": "tunneled", "tunnel": true, "steps": [
    {"call": "bind", "input": {}, "expect": {"output": {"binding": 4}}}
  ]}]}`)
    let (untunneled, unseen) = binder(~network=true)
    let (tunneled, _) = binder(~network=false)
    let skipped = await Run.file(file, untunneled)
    let ran = await Run.file(file, {...tunneled, tunnel: true})
    deepEqual(
      skipped->Array.flatMap(r =>
        r.outcomes->Array.map(
          ((form, outcome)) =>
            switch outcome {
            | Skipped(why) => (form, why->String.includes("binds by a tunnel"))
            | Passed | Failed(_) => (form, false)
            },
        )
      ),
      [(Cbor, true), (Json, true)],
    )
    deepEqual(
      (unseen, ran),
      ([], [{description: "tunneled", outcomes: [(Cbor, Passed), (Json, Passed)]}]),
    )
  },
)
