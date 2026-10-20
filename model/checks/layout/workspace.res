/**
 * The tree's three workspaces, RFC fhg6w: the root's `Cargo.toml` lists every crate beneath `code/`
 * as a member and nothing else, its `rescript.json` every ReScript package as a dependency, and
 * `pnpm-workspace.yaml` takes all beneath `code/`, where every package that pnpm links lies. Cargo and
 * ReScript take no recursive glob, so each list is written out and held here.
 */
open Base

/** What a tool writes, never searched for a package. */
let skipped = ["node_modules", "target", "dist", "generated", "lib"]

/** Every directory beneath `code/` holding the manifest, by its path. */
let rec holding = (path, manifest) => {
  let listed = entries(urlIn(`${path}/`, root), {withFileTypes: true})
  let here = listed->Array.some(e => !(e->isDirectory) && e->entryName == manifest) ? [path] : []
  Array.concat(
    here,
    listed
    ->Array.filter(e => e->isDirectory && !(skipped->Array.includes(e->entryName)))
    ->Array.flatMap(e => holding(`${path}/${e->entryName}`, manifest)),
  )
}

/** The strings in a TOML array under a key of a section, read as the root's manifest writes them. */
let tomlList = (text, section, key) => {
  let at = ref("")
  let collecting = ref(false)
  let got = []
  text
  ->String.split("\n")
  ->Array.forEach(raw => {
    let line = raw->String.trim
    if line->String.startsWith("[") && !collecting.contents {
      at := line
    } else if at.contents == section && line->String.startsWith(key) {
      collecting := !(line->String.includes("]"))
      line
      ->String.split("\"")
      ->Array.forEachWithIndex((s, i) => mod(i, 2) == 1 ? got->Array.push(s) : ())
    } else if collecting.contents {
      collecting := !(line->String.includes("]"))
      line
      ->String.split("\"")
      ->Array.forEachWithIndex((s, i) => mod(i, 2) == 1 ? got->Array.push(s) : ())
    }
  })
  got
}

let differ = (found, what, listed, there) => {
  listed->Array.forEach(x =>
    if !(there->Array.includes(x)) {
      found->Array.push(`${what} lists ${x}, which is not there`)
    }
  )
  there->Array.forEach(x =>
    if !(listed->Array.includes(x)) {
      found->Array.push(`${what} lists not ${x}`)
    }
  )
}

let run = () => {
  let found = []
  let crates = existsSync(urlIn("code/", root)) ? holding("code", "Cargo.toml") : []
  let packages = existsSync(urlIn("code/", root)) ? holding("code", "rescript.json") : []
  if existsSync(urlIn("Cargo.toml", root)) {
    let cargo = readFileSync(urlIn("Cargo.toml", root))
    differ(found, "Cargo.toml", tomlList(cargo, "[workspace]", "members"), crates)
    if !(cargo->String.includes("[package]")) {
      ()
    } else {
      found->Array.push("Cargo.toml: a package at the root, where a virtual manifest alone is")
    }
  } else {
    found->Array.push("no Cargo.toml at the root")
  }
  let names = packages->Array.filterMap(p =>
    switch JSON.parseOrThrow(readFileSync(urlIn(`${p}/rescript.json`, root))) {
    | Object(d) => d->Dict.get("name")->Option.flatMap(JSON.Decode.string)
    | _ => None
    }
  )
  switch JSON.parseOrThrow(readFileSync(urlIn("rescript.json", root))) {
  | Object(d) =>
    let listed = switch d->Dict.get("dependencies") {
    | Some(Array(xs)) => xs->Array.filterMap(JSON.Decode.string)
    | _ => []
    }
    differ(found, "rescript.json", listed, names)
  | _ => found->Array.push("rescript.json: no object")
  }
  let pnpm = readFileSync(urlIn("pnpm-workspace.yaml", root))
  if !(pnpm->String.includes("\"code/**\"")) {
    found->Array.push("pnpm-workspace.yaml takes not code/**")
  }
  dimension(
    "Workspaces",
    "Does the root's Cargo.toml list every crate beneath code/, its rescript.json every ReScript package, and pnpm take code/**?",
    found,
    ~notes=[`crates: ${crates->orNone(", ")}`, `ReScript packages: ${names->orNone(", ")}`],
    (),
  )
}
