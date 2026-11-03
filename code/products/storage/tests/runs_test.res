/***
 * Every run of model/protocol/storage-runs.jsonl replayed against `Operations` through a fake
 * `object` kind gated by actor, its steps taken in their order and its end compared, RFC 13ixj.
 */
open Envelope
open Node

let bucket = 1.
let content = Uint8Array.fromArray([104, 101, 108, 108, 111])
let salt = Uint8Array.fromLength(32)

/** How long an actor is given to make the call its step names, in milliseconds. */
let patience = 2000.

let refuse = message => JsError.throwWithMessage(message)

/** One kind call held until the run's next step names it, `perform` its effect and its answer. */
type gate = (~kind: string, ~name: string, unit => unit) => unit

let gated = (gate: gate, ~kind, ~name, effect: unit => 'answer): promise<'answer> =>
  Promise.make((resolve, _) => gate(~kind, ~name, () => resolve(effect())))

let size = held => held->TypedArray.length->Int.toFloat

/** The `object` kind over `store`, each call passed through `gate` before its effect lands. */
let fake = (store: Dict.t<Uint8Array.t>, gate: gate): Operations.objects => {
  write: call =>
    gated(gate, ~kind="write", ~name=call.name, () => {
      store->Dict.set(call.name, call.content)
      Contracts.Answer.Success(({}: Contracts.ObjectWritten.t))
    }),
  read: call =>
    gated(gate, ~kind="read", ~name=call.name, () =>
      switch store->Dict.get(call.name) {
      | Some(held) =>
        Contracts.Answer.Success({Contracts.ObjectContent.content: held, size: size(held)})
      | None =>
        Contracts.Answer.Error({
          failure: Rejected,
          reason: "not_found",
          message: "nothing is named so",
        })
      }
    ),
  describe: call =>
    gated(gate, ~kind="describe", ~name=call.name, () => Contracts.Answer.Success({
      Contracts.ObjectDescribed.size: ?(store->Dict.get(call.name)->Option.map(size)),
    })),
  delete: call =>
    gated(gate, ~kind="delete", ~name=call.name, () => {
      store->Dict.delete(call.name)
      Contracts.Answer.Success(({}: Contracts.ObjectDeleted.t))
    }),
  list: _ => refuse("a replayed run lists nothing"),
}

/** An object's name and its marker in the kind, learned from one write the code makes alone. */
type named = {object: string, marker: string}

type learned = {first: named, second: named, held: string}

let learnOne = async extension => {
  let log = []
  let objects = fake(Dict.make(), (~kind, ~name, perform) => {
    log->Array.push((kind, name))
    perform()
  })
  let object = switch await Operations.write({salt, objects}, {bucket, content, extension}) {
  | Success(written) => written.object
  | Error(error) => refuse(`a write alone answered ${error.reason}`)
  }
  let named = wanted =>
    switch log->Array.find(((kind, _)) => kind == wanted) {
    | Some((_, name)) => name
    | None => refuse(`a write alone made no ${wanted}`)
    }
  let held = named("describe")
  let marker = switch log
  ->Array.toReversed
  ->Array.find(((kind, name)) => kind == "write" && name != held) {
  | Some((_, name)) => name
  | None => refuse("a write alone wrote no name")
  }
  ({object, marker}, held)
}

/** `N1` is the content under extension `a`, `N2` the same content under `b`. */
let learn = async () => {
  let (first, held) = await learnOne("a")
  let (second, again) = await learnOne("b")
  deepEqual(again, held, ~message="one content is held under one name")
  {first, second, held}
}

let pick = (names, object) =>
  switch object {
  | "N1" => names.first
  | "N2" => names.second
  | other => refuse(`${other} is not an object a run names`)
  }

type task = Write(string) | Delete(string)
type ending = {content: bool, names: array<string>, reads: Dict.t<string>}
type run = {actors: array<(string, task)>, steps: array<string>, ending: ending}

/** A value the run file must hold as `what`, else the replay refuses to start. */
let present = (value, what) =>
  switch value {
  | Some(value) => value
  | None => refuse(`storage-runs.jsonl holds no ${what} where one belongs`)
  }

let entries = json => json->JSON.Decode.object->present("object")
let field = (json, key) => json->entries->Dict.get(key)->present(key)
let text = json => json->JSON.Decode.string->present("string")
let items = json => json->JSON.Decode.array->present("list")

let task = json =>
  switch json->text->String.split(" ") {
  | ["write", object] => Write(object)
  | ["delete", object] => Delete(object)
  | _ => refuse(`${json->text} is not a task`)
  }

let parse = json => {
  let ending = json->field("end")
  {
    actors: json
    ->field("case")
    ->field("actors")
    ->entries
    ->Dict.toArray
    ->Array.map(((actor, value)) => (actor, task(value))),
    steps: json->field("steps")->items->Array.map(text),
    ending: {
      content: ending->field("content")->JSON.Decode.bool->present("boolean"),
      names: ending->field("names")->items->Array.map(text),
      reads: ending
      ->field("reads")
      ->entries
      ->Dict.toArray
      ->Array.map(((name, value)) => (name, text(value)))
      ->Dict.fromArray,
    },
  }
}

/** One run on each line, blank lines skipped. */
let load = () =>
  Runs.readText(Runs.url("../../../../model/protocol/storage-runs.jsonl", Runs.moduleUrl))
  ->String.split("\n")
  ->Array.filter(line => line->String.trim != "")
  ->Array.map(line => line->JSON.parseOrThrow->parse)

let answered = (answer: Contracts.Answer.t<_>) =>
  switch answer {
  | Success(_) => "found"
  | Error({failure: Unavailable}) => "unavailable"
  | Error({failure: Rejected | Unknown, reason}) => reason
  }

let failed = error =>
  switch JsExn.fromException(error)->Option.flatMap(JsExn.message) {
  | Some(message) => message
  | None => "an exception"
  }

type waiting = {action: string, perform: unit => unit}

let replay = async (run, names, label) => {
  let refuse = message => refuse(`${label}: ${message}`)
  let store = Dict.make()
  let waiting: Dict.t<waiting> = Dict.make()
  let crashed = Set.make()
  let finished = Set.make()
  let threw: Dict.t<string> = Dict.make()
  let stray = ref(None)
  let gate = (actor, ~kind, ~name, perform) =>
    if !(crashed->Set.has(actor)) {
      let action = `${kind}-${name == names.held ? "content" : "name"}`
      switch waiting->Dict.get(actor) {
      | Some(_) => stray := Some(`${actor}:${action} called while another call of it waited`)
      | None => waiting->Dict.set(actor, {action, perform})
      }
    }
  run.actors->Array.forEach(((actor, task)) => {
    let context: Operations.context = {salt, objects: fake(store, gate(actor, ...))}
    let started = async () =>
      switch task {
      | Write(object) => {
          let extension = object == "N1" ? "a" : "b"
          let _ = await Operations.write(context, {bucket, content, extension})
        }
      | Delete(object) => {
          let _ = await Operations.delete(context, {bucket, object: pick(names, object).object})
        }
      }
    started()
    ->Promise.thenResolve(() => finished->Set.add(actor))
    ->Promise.catch(error => {
      threw->Dict.set(actor, failed(error))
      finished->Set.add(actor)
      Promise.resolve()
    })
    ->ignore
  })
  let rec call = async (actor, deadline) =>
    switch waiting->Dict.get(actor) {
    | Some(held) => Some(held)
    | None if finished->Set.has(actor) || Date.now() > deadline => None
    | None =>
      await Runs.sleep(1)
      await call(actor, deadline)
    }
  let thrown = () =>
    switch threw->Dict.toArray->Array.get(0) {
    | Some((actor, message)) => refuse(`${actor} threw ${message}`)
    | None => ()
    }
  for index in 0 to run.steps->Array.length - 1 {
    let step = run.steps->Array.getUnsafe(index)
    let at = `step ${Int.toString(index)}, ${step}`
    switch stray.contents {
    | Some(message) => refuse(`${at}: ${message}`)
    | None => ()
    }
    switch step->String.split(":") {
    | ["env", "lose"] => store->Dict.delete(names.held)
    | [actor, "crash"] =>
      crashed->Set.add(actor)
      waiting->Dict.delete(actor)
    | [actor, action] =>
      switch await call(actor, Date.now() +. patience) {
      | None =>
        thrown()
        refuse(`${at}: ${actor} never called ${action}`)
      | Some(held) if held.action != action => refuse(`${at}: ${actor} called ${held.action}`)
      | Some(held) =>
        waiting->Dict.delete(actor)
        held.perform()
      }
    | _ => refuse(`${at}: not a step`)
    }
  }
  let open_ = () =>
    run.actors->Array.filter(((actor, _)) =>
      !(crashed->Set.has(actor)) && !(finished->Set.has(actor))
    )
  let rec finish = async deadline =>
    switch (stray.contents, waiting->Dict.toArray->Array.get(0), open_()->Array.get(0)) {
    | (Some(message), _, _) => refuse(`after the last step: ${message}`)
    | (None, Some((actor, held)), _) => refuse(`${actor}:${held.action} called after the last step`)
    | (None, None, None) => ()
    | (None, None, Some((actor, _))) if Date.now() > deadline => refuse(`${actor} never answered`)
    | (None, None, Some(_)) =>
      await Runs.sleep(1)
      await finish(deadline)
    }
  await finish(Date.now() +. patience)
  thrown()
  let reader: Operations.context = {
    salt,
    objects: fake(store, (~kind as _, ~name as _, perform) => perform()),
  }
  let read = async object =>
    answered(await Operations.read(reader, {bucket, object: pick(names, object).object}))
  {
    content: store->Dict.get(names.held)->Option.isSome,
    names: ["N1", "N2"]->Array.filter(object =>
      store->Dict.get(pick(names, object).marker)->Option.isSome
    ),
    reads: Dict.fromArray([("N1", await read("N1")), ("N2", await read("N2"))]),
  }
}

testAsync("each run TLC makes takes its steps in their order and ends as it says", async () => {
  let runs = load()
  deepEqual(runs->Array.length > 0, true, ~message="storage-runs.jsonl holds a run")
  let names = await learn()
  for index in 0 to runs->Array.length - 1 {
    let run = runs->Array.getUnsafe(index)
    let label = `run ${Int.toString(index)}`
    deepEqual(await replay(run, names, label), run.ending, ~message=label)
  }
})
