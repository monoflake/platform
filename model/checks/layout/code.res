/**
 * The code held to the model, RFC fhg6w: a component's code lies in its layer's directory under the
 * name the model gives it, in the language the model declares, and uses only libraries written in
 * that language. A driver declares none: it lies in its layer's `driver/` as a directory of its
 * implementations, one a kind its grounds give, each in its own, and of its management, in the
 * language its ground asks, `model/ground/drivers.res`. A library lies in `code/libs/`, a manifest
 * for each of its languages. A package is named as the model names what it holds, `@monoflake/` led
 * where it is ReScript's, and namespaced, and MIT OR Apache-2.0, the root's two texts. What
 * `monoflake/cloud` keeps lies nowhere here. Anything not yet written is noted, never refused.
 */
open Base

open Blocks

let manifests: array<(string, lang)> = [("Cargo.toml", #rust), ("rescript.json", #rescript)]

let jsonName = path => {
  let j = JSON.parseOrThrow(readFileSync(urlIn(path, root)))
  (
    j->member("name")->Option.flatMap(JSON.Decode.string),
    j->member("namespace")->Option.flatMap(JSON.Decode.bool),
  )
}

/**
 * A key's text in a Cargo.toml's `[package]`, read a line at a time, as nothing else of it is
 * asked.
 */
let crateKey = (path, key) => {
  let section = ref("")
  let found = ref(None)
  readFileSync(urlIn(path, root))
  ->String.split("\n")
  ->Array.forEach(line => {
    let line = line->String.trim
    if line->String.startsWith("[") {
      section := line
    } else if (
      section.contents == "[package]" &&
        line->String.split("=")->Array.get(0)->Option.map(String.trim) == Some(key)
    ) {
      found := line->String.split("\"")->Array.get(1)
    }
  })
  found.contents
}

let crateName = path => crateKey(path, "name")

let jsonLicense = path =>
  JSON.parseOrThrow(readFileSync(urlIn(path, root)))
  ->member("license")
  ->Option.flatMap(JSON.Decode.string)

/** The names a manifest's tables of dependencies list: package.json's, or a Cargo.toml's. */
let jsonDependencies = path => {
  let j = JSON.parseOrThrow(readFileSync(urlIn(path, root)))
  ["dependencies", "devDependencies", "peerDependencies"]->Array.flatMap(k =>
    j->member(k)->Option.flatMap(JSON.Decode.object)->Option.mapOr([], Dict.keysToArray)
  )
}

let crateDependencies = path => {
  let section = ref("")
  let found = []
  readFileSync(urlIn(path, root))
  ->String.split("\n")
  ->Array.forEach(line => {
    let line = line->String.trim
    switch /^\[((?:dev-|build-)?dependencies)(?:\.([\w-]+))?\]$/->RegExp.exec(line) {
    | Some(m) =>
      switch m->RegExp.Result.matches {
      | [Some(_), Some(name)] =>
        found->Array.push(name)
        section := ""
      | _ => section := "dependencies"
      }
    | None if line->String.startsWith("[") => section := ""
    | None =>
      if section.contents != "" && line != "" && !(line->String.startsWith("#")) {
        line
        ->String.split("=")
        ->Array.get(0)
        ->Option.forEach(k => found->Array.push(k->String.trim))
      }
    }
  })
  found
}

/** Whether a Cargo.toml takes the root's lints, `[lints]` with `workspace = true`. */
let takesLints = path => {
  let section = ref("")
  let found = ref(false)
  readFileSync(urlIn(path, root))
  ->String.split("\n")
  ->Array.forEach(line => {
    let line = line->String.trim
    if line->String.startsWith("[") {
      section := line
    } else if section.contents == "[lints]" && /^workspace\s*=\s*true$/->RegExp.test(line) {
      found := true
    }
  })
  found.contents
}

/**
 * What a block's directory breaks of what the model asks, or none where nothing is written there
 * yet: each language's manifest it is declared in and no other, each naming it, its license, its
 * warnings and lints, and only the packages its `uses` and `takes` allow.
 */
let held = (path, h: held): option<array<string>> => {
  let at = urlIn(`${path}/`, root)
  let files = existsSync(at) ? entries(at, {withFileTypes: true})->Array.map(entryName) : []
  if files->Array.length == 0 {
    None
  } else {
    let found = []
    let allowed = (l: lang) =>
      Array.concat(
        h.uses->Array.map(u => {
          let dir = libraryDir(u)
          l == #rescript ? `@monoflake/${dir}` : dir
        }),
        h.takes->Array.filter(t => t.language == l)->Array.map(t => t.name),
      )
    manifests->Array.forEach(((m, l)) =>
      switch (files->Array.includes(m), h.languages->Array.includes(l)) {
      | (true, false) =>
        found->Array.push(
          `${path}: a ${m}, yet ${h.name} is declared ${h.languages
            ->Array.map(languageName)
            ->Array.join(" and ")}`,
        )
      | (false, true) => found->Array.push(`${path}: no ${m}, yet ${h.name} is ${languageName(l)}`)
      | _ => ()
      }
    )
    if files->Array.includes("Cargo.toml") {
      let manifest = `${path}/Cargo.toml`
      switch crateName(manifest) {
      | Some(n) if n == h.package => ()
      | _ => found->Array.push(`${manifest}: no crate named ${h.package}`)
      }
      if crateKey(manifest, "license") != Some(h.license) {
        found->Array.push(`${manifest}: no license ${h.license}`)
      }
      if !takesLints(manifest) {
        found->Array.push(`${manifest}: no [lints] workspace = true, so the root's lints miss it`)
      }
      crateDependencies(manifest)->Array.forEach(d =>
        if !(allowed(#rust)->Array.includes(d)) {
          found->Array.push(`${manifest}: takes ${d}, which ${h.name} neither uses nor takes`)
        }
      )
    }
    if files->Array.includes("package.json") {
      let manifest = `${path}/package.json`
      if jsonLicense(manifest) != Some(h.license) {
        found->Array.push(`${manifest}: no license ${h.license}`)
      }
      jsonDependencies(manifest)->Array.forEach(d =>
        if !(allowed(#rescript)->Array.includes(d)) {
          found->Array.push(`${manifest}: takes ${d}, which ${h.name} neither uses nor takes`)
        }
      )
    }
    if files->Array.includes("rescript.json") {
      let manifest = `${path}/rescript.json`
      let scoped = `@monoflake/${h.package}`
      switch jsonName(manifest) {
      | (Some(n), Some(true)) if n == scoped => ()
      | _ => found->Array.push(`${manifest}: no package named ${scoped} and namespaced`)
      }
      switch files->Array.includes("package.json")
        ? jsonName(`${path}/package.json`)
        : (None, None) {
      | (Some(n), _) if n == scoped => ()
      | _ => found->Array.push(`${path}: no package.json named ${scoped}, which pnpm links by`)
      }
      let (number, error) = rescriptWarnings
      let warnings = JSON.parseOrThrow(readFileSync(urlIn(manifest, root)))->member("warnings")
      let read = k =>
        warnings->Option.flatMap(w => w->member(k))->Option.flatMap(JSON.Decode.string)
      if read("number") != Some(number) || read("error") != Some(error) {
        found->Array.push(`${manifest}: warnings not number ${number} and error ${error}`)
      }
    }
    found->Array.pushMany(unboundOf(path))
    Some(found)
  }
}

let run = () => {
  let (expected, problems, none) = Blocks.expected()
  let found = problems
  let written = []
  // A directory written holds what the model asks of it.
  let check = (path, h: held) =>
    held(path, h)->Option.forEach(problems => {
      written->Array.push(h.name)
      found->Array.pushMany(problems)
    })
  let inside = path => entries(urlIn(`${path}/`, root), {withFileTypes: true})
  ["apps", "products", "primitives", "substrate", "platform", "libs"]->Array.forEach(g => {
    let at = urlIn(`code/${g}/`, root)
    if existsSync(at) {
      inside(`code/${g}`)
      ->Array.filter(e => e->isDirectory)
      ->Array.forEach(e => {
        let path = `code/${g}/${e->entryName}`
        switch expected->Map.get(path) {
        | None if g == "substrate" && e->entryName == "driver" =>
          inside(path)->Array.forEach(
            v => {
              let at = `${path}/${v->entryName}`
              if !(v->isDirectory) {
                found->Array.push(`${at}: driver/ holds drivers alone`)
              } else if (
                !(
                  expected
                  ->Map.keys
                  ->Array.fromIterator
                  ->Array.some(k => k->String.startsWith(`${at}/`))
                )
              ) {
                found->Array.push(`${at}: no driver of the model lies here`)
              } else {
                inside(at)->Array.forEach(
                  k =>
                    if k->isDirectory {
                      let inner = `${at}/${k->entryName}`
                      switch expected->Map.get(inner) {
                      | Some(h) => check(inner, h)
                      | None =>
                        found->Array.push(
                          `${inner}: neither its management nor a kind it implements`,
                        )
                      }
                    } else {
                      found->Array.push(
                        `${at}/${k->entryName}: a driver holds its implementations and its management alone`,
                      )
                    },
                )
              }
            },
          )
        | None => found->Array.push(`${path}: nothing of the model lies here`)
        | Some(h) => check(path, h)
        }
      })
    }
  })
  // The root holds the two texts as Rust's projects do, and nothing else of licensing, RFC fhg6w.
  ["LICENSE-MIT", "LICENSE-APACHE"]->Array.forEach(t =>
    if !existsSync(urlIn(t, root)) {
      found->Array.push(`no ${t} at the root`)
    }
  )
  ["LICENSE", "LICENSES/", "REUSE.toml"]->Array.forEach(t =>
    if existsSync(urlIn(t, root)) {
      found->Array.push(`${t}: the two texts at the root say all of it`)
    }
  )
  // Each `%todo` and `todo!` names a row still open, so closing one lists the code that waited on it.
  let rows = openRows()
  let waiting = []
  expected->Map.forEachWithKey((h, path) =>
    if written->Array.includes(h.name) {
      todosOf(path)->Array.forEach(((at, named)) =>
        switch named {
        | Some(id) if rows->Array.includes(id) => waiting->Array.push(`${at}: ${id}`)
        | Some(id) => found->Array.push(`${at}: waits on ${id}, which is no open row`)
        | None => found->Array.push(`${at}: a todo naming no row of the checklist`)
        }
      )
    }
  )
  let unwritten =
    expected
    ->Map.values
    ->Array.fromIterator
    ->Array.filter(h => !(written->Array.includes(h.name)))
  dimension(
    "Code",
    "Does each component's code lie in its layer's directory, named as the model names it, in the language the model declares, using only libraries written in it, each package named and namespaced as the model names it?",
    found,
    ~notes=[
      `written: ${written->orNone(", ")}`,
      `waiting on an open row: ${waiting->orNone("; ")}`,
      `not yet written: ${int(
          unwritten->Array.length,
        )}, components, implementations, managements and libraries`,
      `no code of the platform's: ${none->orNone(", ")}`,
      ...Drivers.drivers
      ->Dict.toArray
      ->Array.map(((n, d)) =>
        `${n}: management in ${languageName(d.management)}; ${d.implements
          ->Array.map(i => `${(i.kind :> string)} in ${languageName(i.language)}`)
          ->Array.join(", ")}`
      ),
    ],
    (),
  )
}
