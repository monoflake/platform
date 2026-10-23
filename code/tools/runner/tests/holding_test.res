/***
 * `Holding` held to RFC p8e8k, a case's capacity applied through management on its binding and
 * waited on until it is made, what cannot be set up skipped and what fails said.
 */
open Node

/** A management in memory, its item made after so many describes, each call kept. */
let management = (~making=1, ~state="made", ~apply: option<Run.answered>=?, ~items="[]") => {
  let calls = []
  let described = ref(0)
  let applied = ref(false)
  let call = async (~interface, ~operation, ~input, ~form, ~as_ as _) => {
    calls->Array.push((interface, operation, input, form))
    switch operation {
    | "describe" =>
      let item = applied.contents
        ? {
            described := described.contents + 1
            let name = described.contents > making ? state : "making"
            `[{"id": 1, "capacity": {"name": "container", "millicores": 1, "memory": 1}, "state": {"name": "${name}", "reason": "fault", "message": "no room"}}]`
          }
        : items
      Ok(
        Run.Answered(
          JSON.parseOrThrow(`{"generation": 4, "policy": 0, "grace": 0, "items": ${item}}`),
        ),
      )
    | "apply" =>
      applied := true
      Ok(apply->Option.getOr(Run.Answered(JSON.parseOrThrow(`{"generation": 5}`))))
    | _ => Error(`no ${operation}`)
    }
  }
  let clock = ref(0.)
  let waits = []
  let given = Holding.given(
    ~call,
    ~now=() => clock.contents,
    ~wait=async ms => {
      waits->Array.push(ms)
      clock := clock.contents +. Int.toFloat(ms)
    },
    ~held=dict{"object": JSON.parseOrThrow(`{"size": 1024}`)},
  )
  (given, calls, waits)
}

let operations = calls => calls->Array.map(((_, operation, _, _)) => operation)

testAsync("a case given its container is held it, applied and waited on until made", async () => {
  let (given, calls, waits) = management(~making=2)
  let held = await given(
    ~interface="deployments",
    ~form=Json,
    Some(JSON.parseOrThrow(`{"millicores": 500, "memory": 268435456}`)),
  )
  deepEqual(held, Ok())
  deepEqual(operations(calls), ["describe", "apply", "describe", "describe", "describe"])
  deepEqual(waits, [100, 200])
  let (_, _, list, form) = calls->Array.getUnsafe(1)
  deepEqual(form, Run.Json)
  let item = list->JSON.Decode.object->Option.flatMap(o => o->Dict.get("items"))
  deepEqual(
    list->JSON.Decode.object->Option.flatMap(o => o->Dict.get("generation")),
    Some(JSON.Number(5.)),
  )
  let item = item->Option.flatMap(JSON.Decode.array)->Option.flatMap(i => i->Array.get(0))
  let fieldOf = name =>
    item->Option.flatMap(JSON.Decode.object)->Option.flatMap(o => o->Dict.get(name))
  deepEqual(fieldOf("id"), Some(JSON.Number(1.)))
  deepEqual(
    fieldOf("capacity"),
    Some(JSON.parseOrThrow(`{"millicores": 500, "memory": 268435456, "name": "container"}`)),
  )
  let credential =
    fieldOf("credentials")
    ->Option.flatMap(JSON.Decode.array)
    ->Option.flatMap(c => c->Array.get(0))
    ->Option.flatMap(JSON.Decode.string)
  ok(credential->Option.mapOr(false, c => /^[0-9a-f]{64}$/->RegExp.test(c)))
})

testAsync("a case given nothing is held what its interface is held, or else nothing", async () => {
  let (given, calls, _) = management()
  deepEqual(await given(~interface="object", ~form=Cbor, None), Ok())
  let (_, _, list, form) = calls->Array.getUnsafe(1)
  deepEqual(form, Run.Cbor)
  ok(JSON.stringify(list)->String.includes(`"name":"object"`))
  let (given, calls, _) = management()
  deepEqual(await given(~interface="deployments", ~form=Cbor, None), Ok())
  deepEqual(calls, [])
})

testAsync("a given of what no capacity holds is skipped, and nothing is called", async () => {
  let (given, calls, _) = management()
  deepEqual(
    await given(~interface="authority", ~form=Json, Some(JSON.parseOrThrow(`{"rows": []}`))),
    Error(
      Filling.Unoffered(
        "a given of authority, which holds no capacity a driver's management makes",
      ),
    ),
  )
  deepEqual(calls, [])
})

testAsync("an apply refused, an item failed or a binding holding one already is said", async () => {
  let failed: Run.answered = Failed({
    failure: "unknown",
    reason: "fault",
    message: "waits on 4elqc",
  })
  let (given, _, _) = management(~apply=failed)
  deepEqual(
    await given(~interface="object", ~form=Json, None),
    Error(Filling.Unwritten("management apply answered unknown fault, waits on 4elqc")),
  )
  let (given, _, _) = management(~state="failed")
  deepEqual(
    await given(~interface="object", ~form=Json, None),
    Error(Filling.Unwritten("the item applied failed, fault no room")),
  )
  let (given, calls, _) = management(
    ~items=`[{"id": 3, "capacity": {"name": "object", "size": 1}, "state": {"name": "making"}}]`,
  )
  ok((await given(~interface="object", ~form=Json, None))->Result.isError)
  deepEqual(operations(calls), ["describe"])
})

testAsync("an item never made is given up on once its time is past", async () => {
  let (given, _, waits) = management(~making=100000)
  deepEqual(
    await given(~interface="object", ~form=Json, None),
    Error(
      Filling.Unwritten(`the item applied is not made within ${Int.toString(Holding.making)} ms`),
    ),
  )
  ok(waits->Array.reduce(0, (sum, ms) => sum + ms) >= Holding.making)
})

test("a given naming its own capacity, a volume, is held as named", () => {
  let volume = JSON.parseOrThrow(`{"name": "volume", "size": 4096}`)
  deepEqual(Holding.capacity(~interface="deployments", volume), Some(volume))
  deepEqual(Holding.capacity(~interface="authority", volume), Some(volume))
  deepEqual(
    Holding.capacity(~interface="object", JSON.parseOrThrow(`{"size": 1}`)),
    Some(JSON.parseOrThrow(`{"size": 1, "name": "object"}`)),
  )
  deepEqual(Holding.capacity(~interface="authority", JSON.parseOrThrow(`{"rows": []}`)), None)
})
