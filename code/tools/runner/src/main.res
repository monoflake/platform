/***
 * Runs each behavior file's cases against the implementation at `base` over HTTP, RFC p8e8k, as
 * `usage` says. It prints the chain's root and certificates first.
 */
let usage = "node src/main.res.mjs --base <url> [--bounds <json file>] [--components a,b] <behavior file>..."

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

type tally = {mutable passed: int, mutable failed: int, mutable skipped: int}

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
        let tally = {passed: 0, failed: 0, skipped: 0}
        let rec each = async n =>
          switch files->Array.get(n) {
          | None => ()
          | Some((path, file)) =>
            let own = bounds->Dict.get(file.interface)->Option.getOr(dict{})
            let target = Http.target(~base, ~chain, ~bounds=Dict.assign(own->Dict.copy, given))
            Console.log(`${path}, ${file.interface}:`)
            let results = await Run.file(file, target)
            results->Array.forEach(result =>
              result.outcomes->Array.forEach(((form, outcome)) =>
                switch outcome {
                | Passed =>
                  tally.passed = tally.passed + 1
                  Console.log(`  passed  ${formName(form)}  ${result.description}`)
                | Failed({step, why}) =>
                  tally.failed = tally.failed + 1
                  Console.log(
                    `  failed  ${formName(form)}  ${result.description}, at step ${Int.toString(
                        step,
                      )}: ${why}`,
                  )
                | Skipped(why) =>
                  tally.skipped = tally.skipped + 1
                  Console.log(`  skipped ${formName(form)}  ${result.description}: ${why}`)
                }
              )
            )
            await each(n + 1)
          }
        await each(0)
        let count = Int.toString
        let run = files->Array.length
        Console.log(
          `${count(tally.passed)} passed, ${count(tally.failed)} failed, ${count(
              tally.skipped,
            )} skipped, each case once in each form, of ${count(run)} behavior file${run == 1
              ? ""
              : "s"}`,
        )
        Host.setExitCode(Host.process, tally.failed > 0 || refused.contents ? 1 : 0)
      }
    }
  }
}

await main()
