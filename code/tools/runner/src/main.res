/***
 * Runs each behavior file's cases against the implementation at `base` over HTTP, RFC p8e8k, as
 * `usage` says. It prints the chain's root and certificates first.
 */
let usage = "node src/main.res.mjs --base <url> [--bounds <json file>] [--components a,b] [--tokens <file or ->] [--waits <json file>] <behavior file>..."

let refuse = why => {
  Console.error(`runner: ${why}`)
  Host.setExitCode(Host.process, 2)
}

/** The arguments, each flag's value by its name, and the files. */
let rec parse = (args, flags, files) =>
  switch args {
  | list{flag, value, ...rest} if flag->String.startsWith("--") =>
    flags->Dict.set(flag->String.slice(~start=2), value)
    parse(rest, flags, files)
  | list{flag} if flag->String.startsWith("--") => Error(`${flag} without its value`)
  | list{file, ...rest} => parse(rest, flags, files->Array.concat([file]))
  | list{} => Ok((flags, files))
  }

let readText = path =>
  try Ok(Host.readFileSync(path)) catch {
  | JsExn(e) => Error(`${path}: ${e->JsExn.message->Option.getOr("not read")}`)
  }

/** Numbers by name, as a bounds file and an interface's `bounds` write them. */
let numbers = json =>
  json
  ->JSON.Decode.object
  ->Option.mapOr([], Dict.toArray)
  ->Array.filterMap(((name, value)) => value->JSON.Decode.float->Option.map(n => (name, n)))
  ->Dict.fromArray

/** Each interface's own bounds, by its name. */
let interfaceBounds = () =>
  switch JSON.parseOrThrow(Host.fromRoot("model/contracts.json")) {
  | contracts =>
    contracts
    ->JSON.Decode.object
    ->Option.flatMap(o => o->Dict.get("interfaces"))
    ->Option.flatMap(JSON.Decode.object)
    ->Option.mapOr(dict{}, interfaces =>
      interfaces->Dict.mapValues(i =>
        i
        ->JSON.Decode.object
        ->Option.flatMap(o => o->Dict.get("bounds"))
        ->Option.mapOr(dict{}, numbers)
      )
    )
  | exception JsExn(_) => dict{}
  }

/** Whether a file is a property, which only a history of a run shows. */
let isProperty = text =>
  switch JSON.parseOrThrow(text) {
  | json => json->JSON.Decode.object->Option.flatMap(o => o->Dict.get("checker")) != None
  | exception JsExn(_) => false
  }

let formName = (form: Run.form) =>
  switch form {
  | Cbor => "cbor"
  | Json => "json"
  }

type tally = {mutable passed: int, mutable failed: int, mutable waiting: int, mutable skipped: int}

let counted = tally =>
  `${Int.toString(tally.passed)} passed, ${Int.toString(tally.failed)} failed, ${Int.toString(
      tally.waiting,
    )} waiting, ${Int.toString(tally.skipped)} skipped`

/** A case's outcome in a form printed, and counted in each tally. */
let told = (tallies, form, description, reported: Waiting.reported) => {
  let form = formName(form)
  switch reported {
  | Ran(Passed) =>
    tallies->Array.forEach(t => t.passed = t.passed + 1)
    Console.log(`  passed  ${form}  ${description}`)
  | Ran(Failed({step, why})) =>
    tallies->Array.forEach(t => t.failed = t.failed + 1)
    Console.log(`  failed  ${form}  ${description}, at step ${Int.toString(step)}: ${why}`)
  | Waiting(on) =>
    tallies->Array.forEach(t => t.waiting = t.waiting + 1)
    Console.log(`  waiting ${form}  ${description}: on ${on}`)
  | Ran(Skipped(why)) =>
    tallies->Array.forEach(t => t.skipped = t.skipped + 1)
    Console.log(`  skipped ${form}  ${description}: ${why}`)
  }
}

let main = async () => {
  switch parse(List.fromArray(Host.argv->Array.slice(~start=2)), Dict.make(), []) {
  | Error(why) => refuse(`${why}; ${usage}`)
  | Ok((flags, paths)) =>
    switch (flags->Dict.get("base"), paths) {
    | (None, _) | (_, []) => refuse(usage)
    | (Some(base), paths) =>
      let given = switch flags->Dict.get("bounds") {
      | None => Ok(dict{})
      | Some(path) =>
        readText(path)->Result.flatMap(text =>
          try Ok(numbers(JSON.parseOrThrow(text))) catch {
          | JsExn(_) => Error(`${path}: no JSON`)
          }
        )
      }
      switch given {
      | Error(why) => refuse(why)
      | Ok(given) =>
        let refused = ref(false)
        let files = paths->Array.filterMap(path =>
          switch readText(path) {
          | Error(why) =>
            Console.log(why)
            refused := true
            None
          | Ok(text) =>
            switch Sample.read(text) {
            | Ok(file) => Some((path, file))
            | Error(_) if isProperty(text) =>
              Console.log(`${path}: a property, its checker left for later by RFC p8e8k`)
              None
            | Error(why) =>
              Console.log(`${path}: no behavior file, ${why}`)
              refused := true
              None
            }
          }
        )
        let named =
          flags
          ->Dict.get("components")
          ->Option.mapOr([], list => list->String.split(",")->Array.filter(name => name != ""))
        let called = files->Array.flatMap(((_, file: Sample.file)) =>
          file.cases->Array.flatMap(c =>
            c.steps->Array.filterMap(
              step =>
                switch step {
                | Call({as_}) => as_
                | Send(_) | Lose(_) | Wait(_) => None
                },
            )
          )
        )
        let components = Set.fromArray(named->Array.concat(called))->Set.values->Array.fromIterator
        let chain = components == [] ? None : Some(Http.chain(~components, ~now=Date.now()))
        switch chain {
        | Some(chain) =>
          Console.log(
            `root: ${Web.base64url(Http.root(chain))}, signing as ${components->Array.join(", ")}`,
          )
          Http.certificates(chain)->Array.forEach(certificate =>
            Console.log(`certificate: ${Web.base64url(certificate)}`)
          )
        | None => ()
        }
        let bounds = interfaceBounds()
        let needed =
          files->Array.reduce(0, (n, (_, file: Sample.file)) => n + file.cases->Array.length * 2)
        let tokens = switch flags->Dict.get("tokens") {
        | None => Ok(None)
        | Some(path) =>
          (
            path == "-"
              ? (await Host.readStdin())->Result.mapError(why => `stdin: ${why}`)
              : readText(path)
          )->Result.flatMap(text =>
            switch Bearer.tokens(text) {
            | tokens if tokens->Array.length >= needed => Ok(Some(tokens))
            | tokens =>
              Error(
                `${path == "-" ? "stdin" : path}: ${Int.toString(
                    tokens->Array.length,
                  )} tokens for ${Int.toString(needed)} bindings, one for each case in each form`,
              )
            }
          )
        }
        let rules = switch flags->Dict.get("waits") {
        | None => Ok([])
        | Some(path) =>
          readText(path)->Result.flatMap(text =>
            Waiting.read(text)->Result.mapError(why => `${path}: ${why}`)
          )
        }
        switch (tokens, rules) {
        | (Error(why), _) | (_, Error(why)) => refuse(why)
        | (Ok(tokens), Ok(rules)) =>
          let total = {passed: 0, failed: 0, waiting: 0, skipped: 0}
          let taken = ref(0)
          // Each token taken in turn, the next binding a case's CBOR or JSON runs on.
          let next = tokens =>
            () => {
              taken := taken.contents + 1
              tokens->Array.get(taken.contents - 1)->Option.getOr("")
            }
          let rec each = async n =>
            switch files->Array.get(n) {
            | None => ()
            | Some((path, file)) =>
              let own = bounds->Dict.get(file.interface)->Option.getOr(dict{})
              let bounds = Dict.assign(own->Dict.copy, given)
              Console.log(`${path}, ${file.interface}:`)
              let tally = {passed: 0, failed: 0, waiting: 0, skipped: 0}
              let results = switch tokens {
              | None =>
                (
                  await Run.file(file, Http.target(~base, ~chain, ~bounds))
                )->Array.filterMapWithIndex((result, k) =>
                  file.cases->Array.get(k)->Option.map(case => (case, result))
                )
              | Some(tokens) =>
                await Bearer.file(
                  file,
                  ~at=(~token) => Http.target(~base, ~chain, ~bounds, ~token),
                  ~next=next(tokens),
                )
              }
              results->Array.forEach(((case, result)) =>
                result.outcomes->Array.forEach(((form, outcome)) =>
                  told(
                    [tally, total],
                    form,
                    result.description,
                    Waiting.reported(rules, ~interface=file.interface, ~case, outcome),
                  )
                )
              )
              Console.log(`  ${counted(tally)}`)
              await each(n + 1)
            }
          await each(0)
          let run = files->Array.length
          Console.log(
            `${counted(total)}, each case once in each form, of ${Int.toString(
                run,
              )} behavior file${run == 1 ? "" : "s"}`,
          )
          Host.setExitCode(Host.process, total.failed > 0 || refused.contents ? 1 : 0)
        }
      }
    }
  }
}

await main()
