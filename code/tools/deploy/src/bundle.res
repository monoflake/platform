module Contracts = Envelope.Contracts

type config = {main: string, compatibilityDate: string, compatibilityFlags: array<string>}

/** The index past the end of what starts at `from`, `ending` included, or the text's end. */
let past = (text, from, ending) =>
  switch text->String.indexOfFrom(ending, from) {
  | -1 => text->String.length
  | at => at + ending->String.length
  }

/** The next character that is no whitespace from an index, or none. */
let rec nextShown = (text, at) =>
  switch text->String.charAt(at) {
  | "" => None
  | " " | "\t" | "\n" | "\r" => nextShown(text, at + 1)
  | c => Some(c)
  }

/** The text with what `drop` says to leave out of it outside strings, a string kept whole. */
let scanned = (text, drop) => {
  let kept = []
  let rec go = (at, inString) =>
    switch text->String.charAt(at) {
    | "" => ()
    | "\\" if inString =>
      kept->Array.push(text->String.slice(~start=at, ~end=at + 2))
      go(at + 2, true)
    | "\"" =>
      kept->Array.push("\"")
      go(at + 1, !inString)
    | c if inString =>
      kept->Array.push(c)
      go(at + 1, true)
    | c =>
      switch drop(at) {
      | Some(next) => go(next, false)
      | None =>
        kept->Array.push(c)
        go(at + 1, false)
      }
    }
  go(0, false)
  kept->Array.join("")
}

let uncommented = text => {
  let bare = text->scanned(at =>
    switch text->String.slice(~start=at, ~end=at + 2) {
    // A line comment ends before its newline, which is kept.
    | "//" =>
      switch text->String.indexOfFrom("\n", at) {
      | -1 => Some(text->String.length)
      | newline => Some(newline)
      }
    | "/*" => Some(past(text, at + 2, "*/"))
    | _ => None
    }
  )
  bare->scanned(at =>
    switch (bare->String.charAt(at), nextShown(bare, at + 1)) {
    | (",", Some("}" | "]")) => Some(at + 1)
    | _ => None
    }
  )
}

let dated = /^\d{4}-\d{2}-\d{2}$/

let config = text =>
  switch JSON.parseOrThrow(uncommented(text)) {
  | exception JsExn(e) => Error(`no JSON, ${e->JsExn.message->Option.getOr("not parsed")}`)
  | json =>
    let o = json->JSON.Decode.object->Option.getOr(dict{})
    let text = name => o->Dict.get(name)->Option.flatMap(JSON.Decode.string)
    let flags =
      o
      ->Dict.get("compatibility_flags")
      ->Option.mapOr(Some([]), f =>
        f
        ->JSON.Decode.array
        ->Option.flatMap(f => {
          let named = f->Array.filterMap(JSON.Decode.string)
          named->Array.length == f->Array.length ? Some(named) : None
        })
      )
    switch (text("main"), text("compatibility_date"), flags) {
    | (None, _, _) => Error("no main, the Worker's entry")
    | (_, None, _) => Error("no compatibility_date")
    | (_, Some(date), _) if !(dated->RegExp.test(date)) =>
      Error(`compatibility_date ${date} is not YYYY-MM-DD`)
    | (_, _, None) => Error("compatibility_flags are not strings")
    | (Some(main), Some(compatibilityDate), Some(compatibilityFlags)) =>
      Ok({main, compatibilityDate, compatibilityFlags})
    }
  }

let declared = text =>
  switch JSON.parseOrThrow(text) {
  | exception JsExn(e) => Error(`is no JSON, ${e->JsExn.message->Option.getOr("not parsed")}`)
  | json =>
    switch json->JSON.Decode.object {
    | None => Error("is no JSON object")
    | Some(o) =>
      switch (
        o->Dict.keysToArray->Array.find(key => key != "kinds" && key != "ingress"),
        o->Dict.get("kinds"),
      ) {
      | (Some(other), _) => Error(`holds kinds and ingress alone, not ${other}`)
      | (None, None) => Error("holds no kinds")
      | (None, Some(listed)) =>
        let strings = items => {
          let named = items->Array.filterMap(JSON.Decode.string)
          named->Array.length == items->Array.length ? Some(named) : None
        }
        switch listed->JSON.Decode.array->Option.flatMap(strings) {
        | None => Error("declares kinds that are not an array of strings")
        | Some([]) => Error("declares an empty list of kinds")
        | Some(names) =>
          let kind = name =>
            Contracts.DeploymentKind.fromJson(JSON.String(name))->Result.mapOr(None, k => Some(k))
          switch (
            names->Array.find(name => kind(name) == None),
            names->Array.findWithIndex((name, at) => names->Array.indexOf(name) != at),
          ) {
          | (Some(name), _) => Error(`declares kind ${name}, not function, instance or container`)
          | (None, Some(name)) => Error(`declares kind ${name} twice`)
          | (None, None) => Ok(names->Array.filterMap(kind))
          }
        }
      }
    }
  }

type release = {
  kinds: option<array<Contracts.DeploymentKind.t>>,
  ingress: option<array<Contracts.AppIngress.t>>,
}

let release = (~ingress as given=?, text) => {
  let parsed = switch JSON.parseOrThrow(text) {
  | json => Ok(json)
  | exception JsExn(_) => Error("is no JSON")
  }
  parsed->Result.flatMap(json =>
    switch json->JSON.Decode.object {
    | None => Error("is no JSON object")
    | Some(o) if given != None && o->Dict.has("ingress") =>
      Error("and --ingress both declare ingress")
    | Some(o) =>
      let kinds = o->Dict.has("kinds") ? declared(text)->Result.map(k => Some(k)) : Ok(None)
      let ingress = switch o->Dict.get("ingress") {
      | None => Ok(given)
      | Some(json) =>
        switch json->JSON.Decode.array {
        | None => Error("declares ingress that is not an array")
        | Some(items) =>
          items
          ->Array.reduce(Ok([]), (all, item) =>
            all->Result.flatMap(
              all =>
                Contracts.AppIngress.fromJson(item)
                ->Result.mapError(_ => "declares malformed ingress")
                ->Result.map(
                  i => {
                    all->Array.push(i)
                    all
                  },
                ),
            )
          )
          ->Result.map(items => Some(items))
        }
      }
      switch o->Dict.keysToArray->Array.find(key => key != "kinds" && key != "ingress") {
      | Some(other) => Error("holds kinds and ingress alone, not " ++ other)
      | None => kinds->Result.flatMap(kinds => ingress->Result.map(ingress => {kinds, ingress}))
      }
    }
  )
}

let mainModule = config => {
  let file = config.main->String.split("/")->Array.at(-1)->Option.getOr(config.main)
  switch file->String.lastIndexOf(".") {
  | at if at > 0 => file->String.slice(~start=0, ~end=at) ++ ".js"
  | _ => file ++ ".js"
  }
}

let isModule = name => name != "README.md" && !(name->String.endsWith(".map"))

let metadata = (~kinds=?, ~ingress=?, config) => {
  let fields = dict{
    "main_module": JSON.String(mainModule(config)),
    "compatibility_date": JSON.String(config.compatibilityDate),
  }
  if config.compatibilityFlags->Array.length > 0 {
    fields->Dict.set(
      "compatibility_flags",
      JSON.Array(config.compatibilityFlags->Array.map(f => JSON.String(f))),
    )
  }
  // Kinds go last and only where declared, so an undeclared bundle is the same bytes, emgxf.
  ingress->Option.forEach(i =>
    fields->Dict.set("ingress", JSON.Array(i->Array.map(Contracts.AppIngress.toJson)))
  )
  kinds->Option.forEach(kinds =>
    fields->Dict.set("kinds", JSON.Array(kinds->Array.map(Contracts.DeploymentKind.toJson)))
  )
  JSON.stringify(JSON.Object(fields))
}

type file = {name: string, bytes: Uint8Array.t}

let block = 512

/** A number in octal digits, zeros before it to `width`, then a NUL. */
let octal = (n, width) => Int.toString(n, ~radix=8)->String.padStart(width - 1, "0") ++ "\x00"

/** A file's header, its checksum the sum of its bytes with that field read as spaces. */
let header = (file, name) => {
  let h = Uint8Array.fromLength(block)
  let put = (at, text) => h->Bytes.copyInto(Bytes.utf8(text), at)
  h->Bytes.copyInto(name, 0)
  put(100, octal(0o644, 8))
  put(108, octal(0, 8))
  put(116, octal(0, 8))
  put(124, octal(file.bytes->TypedArray.length, 12))
  put(136, octal(0, 12))
  put(148, "        ")
  put(156, "0")
  put(257, "ustar\x0000")
  let sum = ref(0)
  for at in 0 to block - 1 {
    sum := sum.contents + h->TypedArray.get(at)->Option.getOr(0)
  }
  put(148, Int.toString(sum.contents, ~radix=8)->String.padStart(6, "0") ++ "\x00 ")
  h
}

/** The bytes a length takes in whole blocks. */
let padded = length => (length + block - 1) / block * block

let tar = files =>
  switch files->Array.find(f => Bytes.utf8(f.name)->TypedArray.length > 100) {
  | Some(f) => Error(`${f.name} is past the 100 bytes a ustar name holds`)
  | None =>
    let total =
      files->Array.reduce(0, (sum, f) => sum + block + padded(f.bytes->TypedArray.length)) +
        2 * block
    let archive = Uint8Array.fromLength(total)
    let at = ref(0)
    files->Array.forEach(f => {
      archive->Bytes.copyInto(header(f, Bytes.utf8(f.name)), at.contents)
      archive->Bytes.copyInto(f.bytes, at.contents + block)
      at := at.contents + block + padded(f.bytes->TypedArray.length)
    })
    Ok(archive)
  }

let packed = (~kinds=?, ~ingress=?, config, files) => {
  let modules =
    files
    ->Array.filter(f => isModule(f.name) && f.name != "metadata.json")
    ->Array.toSorted((a, b) => String.compare(a.name, b.name))
  let main = mainModule(config)
  modules->Array.some(f => f.name == main)
    ? tar(
        [
          {name: "metadata.json", bytes: Bytes.utf8(metadata(~kinds?, ~ingress?, config))},
          ...modules,
        ],
      )
    : Error(`wrangler wrote no ${main}, the main module`)
}
