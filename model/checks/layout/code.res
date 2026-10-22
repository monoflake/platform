/**
 * The code held to the model, each component in its layer's directory under its name and language,
 * each library in `code/libs/`, RFC fhg6w. Anything not yet written is noted, never refused.
 */
open Base

open Blocks

let manifests: array<(string, lang)> = [
  ("Cargo.toml", #rust),
  ("rescript.json", #rescript),
  ("default.nix", #nix),
  ("docker-bake.hcl", #docker),
]

type stats
@module("node:fs") external lstatSync: url => stats = "lstatSync"
@send external isSymbolicLink: stats => bool = "isSymbolicLink"
@module("node:fs") external realpathSync: url => string = "realpathSync"

/** The root's two texts, which every package links beside its manifests, so each carries them. */
let texts = ["LICENSE-MIT", "LICENSE-APACHE"]

/** Whether a package's `text` is a link resolving to the root's own. */
let linked = (root, path, text) => {
  let at = urlIn(`${path}/${text}`, root)
  existsSync(at) &&
  lstatSync(at)->isSymbolicLink &&
  realpathSync(at) == realpathSync(urlIn(text, root))
}

let jsonName = (root, path) => {
  let j = JSON.parseOrThrow(readFileSync(urlIn(path, root)))
  (
    j->member("name")->Option.flatMap(JSON.Decode.string),
    j->member("namespace")->Option.flatMap(JSON.Decode.string),
  )
}

/**
 * A key's text in a Cargo.toml's `[package]`, read a line at a time, as nothing else of it is
 * asked.
 */
let crateKey = (root, path, key) => {
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

let crateName = (root, path) => crateKey(root, path, "name")

let jsonLicense = (root, path) =>
  JSON.parseOrThrow(readFileSync(urlIn(path, root)))
  ->member("license")
  ->Option.flatMap(JSON.Decode.string)

/** The names a manifest's tables of dependencies list, package.json's or a Cargo.toml's. */
let jsonDependencies = (root, path) => {
  let j = JSON.parseOrThrow(readFileSync(urlIn(path, root)))
  ["dependencies", "devDependencies", "peerDependencies"]->Array.flatMap(k =>
    j->member(k)->Option.flatMap(JSON.Decode.object)->Option.mapOr([], Dict.keysToArray)
  )
}

let crateDependencies = (root, path) => {
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

/** A dependency's requirement as a Cargo.toml writes it inline, none where it names none. */
let quoted = /^"([^"]+)"$/
let inline = /version\s*=\s*"([^"]+)"/
let crateRequirement = (root, path, name) =>
  readFileSync(urlIn(path, root))
  ->String.split("\n")
  ->Array.findMap(line =>
    switch line->String.trim->String.split("=")->Array.get(0)->Option.map(String.trim) {
    | Some(k) if k == name => {
        let value =
          line
          ->String.trim
          ->String.slice(~start=line->String.trim->String.indexOf("=") + 1)
          ->String.trim
        switch (quoted->RegExp.exec(value), inline->RegExp.exec(value)) {
        | (Some(m), _) | (None, Some(m)) =>
          m->RegExp.Result.matches->Array.get(0)->Option.flatMap(x => x)
        | (None, None) => None
        }
      }
    | _ => None
    }
  )

/** A package.json's requirement for a dependency, none where it is not a version. */
let jsonRequirement = (root, path, name) => {
  let j = JSON.parseOrThrow(readFileSync(urlIn(path, root)))
  ["dependencies", "devDependencies", "peerDependencies"]->Array.findMap(k =>
    j
    ->member(k)
    ->Option.flatMap(JSON.Decode.object)
    ->Option.flatMap(d => d->Dict.get(name))
    ->Option.flatMap(JSON.Decode.string)
  )
}

/** Whether a requirement stays within a major, `0.11` taking `0.11.2` and `1` taking `^1.4`. */
let operators = /^[\^~=<>\s]+/
let within = (requirement, major) => {
  let bare = requirement->String.replaceRegExp(operators, "")
  bare == major || bare->String.startsWith(`${major}.`)
}

/** Whether a Cargo.toml takes the root's lints, `[lints]` with `workspace = true`. */
let takesLints = (root, path) => {
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

/** What a block's directory breaks of what the model asks, or none where nothing is written yet. */
let held = (tree: tree, path, h: held): option<array<string>> => {
  let root = tree.root
  let at = urlIn(`${path}/`, root)
  // A block's directory beneath this one is its own, never this block's.
  let files = existsSync(at)
    ? entries(at, {withFileTypes: true})
      ->Array.filter(e => !(e->isDirectory && tree.blocks->Map.has(`${path}/${e->entryName}`)))
      ->Array.map(entryName)
    : []
  if files->Array.length == 0 {
    None
  } else {
    let found = []
    let allowed = (l: lang) =>
      Array.concatMany(
        [],
        [
          h.uses->Array.map(u => {
            let dir = libraryDir(u)
            l == #rescript ? `@monoflake/${dir}` : dir
          }),
          h.takes->Array.filter(t => (t.language :> lang) == l)->Array.map(t => t.name),
          l == #rust ? h.writtenBy->Option.mapOr([], w => [w]) : [],
        ],
      )
    // Each package taken at the major the model names, where its manifest writes a version.
    let majors = (l: lang, manifest, requirement) =>
      h.takes
      ->Array.filter(t => (t.language :> lang) == l)
      ->Array.forEach(t =>
        switch requirement(root, manifest, t.name) {
        | Some(r) if !within(r, t.major) =>
          found->Array.push(
            `${manifest}: takes ${t.name} at ${r}, where the model gives ${h.name} its major ${t.major}`,
          )
        | _ => ()
        }
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
      switch crateName(root, manifest) {
      | Some(n) if n == h.package => ()
      | _ => found->Array.push(`${manifest}: no crate named ${h.package}`)
      }
      if crateKey(root, manifest, "license") != Some(h.license) {
        found->Array.push(`${manifest}: no license ${h.license}`)
      }
      if crateKey(root, manifest, "version") != Some(unpublished) {
        found->Array.push(`${manifest}: no version ${unpublished}, as nothing is published`)
      }
      if !takesLints(root, manifest) {
        found->Array.push(`${manifest}: no [lints] workspace = true, so the root's lints miss it`)
      }
      crateDependencies(root, manifest)->Array.forEach(d =>
        if !(allowed(#rust)->Array.includes(d)) {
          found->Array.push(`${manifest}: takes ${d}, which ${h.name} neither uses nor takes`)
        }
      )
      majors(#rust, manifest, crateRequirement)
    }
    if files->Array.includes("package.json") {
      let manifest = `${path}/package.json`
      if jsonLicense(root, manifest) != Some(h.license) {
        found->Array.push(`${manifest}: no license ${h.license}`)
      }
      let version =
        JSON.parseOrThrow(readFileSync(urlIn(manifest, root)))
        ->member("version")
        ->Option.flatMap(JSON.Decode.string)
      if version != Some(unpublished) {
        found->Array.push(`${manifest}: no version ${unpublished}, as nothing is published`)
      }
      jsonDependencies(root, manifest)->Array.forEach(d =>
        if !(allowed(#rescript)->Array.includes(d)) {
          found->Array.push(`${manifest}: takes ${d}, which ${h.name} neither uses nor takes`)
        }
      )
      majors(#rescript, manifest, jsonRequirement)
    }
    if files->Array.includes("rescript.json") {
      let manifest = `${path}/rescript.json`
      let scoped = `@monoflake/${h.package}`
      let namespace = namespaceOf(h.package)
      switch jsonName(root, manifest) {
      | (Some(n), Some(ns)) if n == scoped && ns == namespace => ()
      | _ =>
        found->Array.push(
          `${manifest}: no package named ${scoped} and namespaced ${namespace}, its subject's name alone`,
        )
      }
      switch files->Array.includes("package.json")
        ? jsonName(root, `${path}/package.json`)
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
      let (module_, suffix) = rescriptOutput
      let config = JSON.parseOrThrow(readFileSync(urlIn(manifest, root)))
      let specs = list(config->member("package-specs"))->Option.getOr([])
      let inSource = s => truth(s->member("in-source")) == Some(true)
      if (
        !(
          specs->Array.length == 1 &&
            specs->Array.every(s => text(s->member("module")) == Some(module_) && inSource(s))
        ) ||
        text(config->member("suffix")) != Some(suffix)
      ) {
        found->Array.push(`${manifest}: no ${module_} beside its sources as ${suffix}`)
      }
    }
    texts->Array.forEach(text =>
      if !linked(root, path, text) {
        found->Array.push(`${path}/${text}: no link to the root's ${text}`)
      }
    )
    found->Array.pushMany(unboundOf(tree, path))
    Some(found)
  }
}

/** What a tree's blocks break, each written one held to what it asks, with its state and todos. */
type holding = {
  found: array<string>,
  written: array<string>,
  waiting: array<string>,
  unwritten: int,
}

let hold = (tree: tree, ~work="model/plan/work.res") => {
  let found = []
  let written = []
  // What a block fails is the check's once it is accepted, and listed in red while it is in work.
  let into = (h: held) => tree.work->Dict.get(h.package) == Some(InWork) ? inWork : found
  let blocks =
    tree.blocks->Map.entries->Array.fromIterator->Array.toSorted(((a, _), (b, _)) => byText(a, b))
  blocks->Array.forEach(((path, h)) =>
    held(tree, path, h)->Option.forEach(problems => {
      written->Array.push(h.name)
      if tree.work->Dict.get(h.package) == None {
        found->Array.push(`${path}: written, yet ${work} has it neither in work nor accepted`)
      }
      into(h)->Array.pushMany(problems)
    })
  )
  // Each `%todo` and `todo!` names a row still open, so closing one lists the code that waited.
  let waiting = []
  blocks->Array.forEach(((path, h)) =>
    if written->Array.includes(h.name) {
      todosOf(tree, path)->Array.forEach(((at, named)) =>
        switch named {
        | Some(id) if tree.rows->Array.includes(id) => waiting->Array.push(`${at}: ${id}`)
        | Some(id) => into(h)->Array.push(`${at}: waits on ${id}, which is no open row`)
        | None => into(h)->Array.push(`${at}: a todo naming no row of the checklist`)
        }
      )
    }
  )
  tree.work->Dict.forEachWithKey((state, package) =>
    switch (state, blocks->Array.find(((_, h)) => h.package == package)) {
    | (_, None) => found->Array.push(`${work}: ${package}, which is no block's package`)
    | (Accepted, Some((_, h))) if !(written->Array.includes(h.name)) =>
      found->Array.push(`${work}: ${package} accepted, yet nothing of it is written`)
    | (Accepted | InWork, Some(_)) => ()
    }
  )
  let unwritten = blocks->Array.filter(((_, h)) => !(written->Array.includes(h.name)))
  {found, written, waiting, unwritten: unwritten->Array.length}
}

let run = () => {
  let (expected, problems, none) = Blocks.expected()
  let tree = own()
  let held = hold(tree)
  let found = Array.concat(problems, held.found)
  let inside = path => entries(urlIn(`${path}/`, root), {withFileTypes: true})
  ["apps", "products", "primitives", "substrate", "platform", "libs", "tools"]->Array.forEach(g => {
    let at = urlIn(`code/${g}/`, root)
    if existsSync(at) {
      inside(`code/${g}`)
      ->Array.filter(e => e->isDirectory)
      ->Array.forEach(e => {
        let path = `code/${g}/${e->entryName}`
        if expected->Map.get(path)->Option.isNone {
          found->Array.push(`${path}: nothing of the model lies here`)
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
  dimension(
    "Code",
    "Does each component's code lie in its layer's directory, named as the model names it, in the language the model declares, using only libraries written in it, each package named and namespaced as the model names it?",
    found,
    ~notes=[
      `written: ${held.written->orNone(", ")}`,
      `in work: ${tree.work
        ->Dict.toArray
        ->Array.filter(((_, s)) => s == InWork)
        ->Array.map(((p, _)) => p)
        ->orNone(", ")}`,
      `waiting on an open row: ${held.waiting->orNone("; ")}`,
      `not yet written: ${int(held.unwritten)}, components and libraries`,
      `no code of the platform's: ${none->orNone(", ")}`,
    ],
    (),
  )
}
