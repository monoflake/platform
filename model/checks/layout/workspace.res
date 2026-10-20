/**
 * The tree's three workspaces, RFC fhg6w: the root's `Cargo.toml` lists every crate beneath `code/`
 * as a member and nothing else, its `rescript.json` and `package.json` no ReScript package, as each
 * builds alone, and `pnpm-workspace.yaml` takes all beneath `code/`, where every package that pnpm
 * links lies. Cargo takes no recursive glob, so its list is written out and held here.
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

/**
 * The strings in a TOML array under a key of a section, read as the root's manifest writes them.
 */
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

/** Each `key = "value"` of a section of a TOML text, as the root's manifest writes them. */
let tomlValues = (text, section) => {
  let at = ref("")
  let got = []
  text
  ->String.split("\n")
  ->Array.forEach(raw => {
    let line = raw->String.trim
    if line->String.startsWith("[") {
      at := line
    } else if at.contents == section {
      switch line->String.split("=")->Array.map(String.trim) {
      | [k, v] => got->Array.push((k, v->String.replaceAll("\"", "")))
      | _ => ()
      }
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
    // Every crate takes the same lints from here, `docs/code.md`.
    let rust = tomlValues(cargo, "[workspace.lints.rust]")
    let clippy = tomlValues(cargo, "[workspace.lints.clippy]")
    Blocks.rustLints->Array.forEach(((k, level)) =>
      if !(rust->Array.some(((n, v)) => n == k && v == level)) {
        found->Array.push(`Cargo.toml: no ${k} = "${level}" in [workspace.lints.rust]`)
      }
    )
    Blocks.clippyLints->Array.forEach(k =>
      if !(clippy->Array.some(((n, v)) => n == k && v == "deny")) {
        found->Array.push(`Cargo.toml: no ${k} = "deny" in [workspace.lints.clippy]`)
      }
    )
    if !(cargo->String.includes("[package]")) {
      ()
    } else {
      found->Array.push("Cargo.toml: a package at the root, where a virtual manifest alone is")
    }
  } else {
    found->Array.push("no Cargo.toml at the root")
  }
  let names = packages->Array.filterMap(p =>
    JSON.parseOrThrow(readFileSync(urlIn(`${p}/rescript.json`, root)))
    ->member("name")
    ->Option.flatMap(JSON.Decode.string)
  )
  // A block builds alone, so one failing fails no other and never the model, `docs/code.md`.
  switch JSON.parseOrThrow(readFileSync(urlIn("rescript.json", root)))->JSON.Decode.object {
  | Some(d) =>
    list(d->Dict.get("dependencies"))
    ->Option.getOr([])
    ->Array.filterMap(JSON.Decode.string)
    ->Array.filter(n => names->Array.includes(n))
    ->Array.forEach(n =>
      found->Array.push(`rescript.json: ${n} as a dependency, so a block failing fails the model`)
    )
  | None => found->Array.push("rescript.json: no object")
  }
  let linked =
    JSON.parseOrThrow(readFileSync(urlIn("package.json", root)))
    ->member("devDependencies")
    ->Option.flatMap(JSON.Decode.object)
    ->Option.getOr(Dict.make())
  names->Array.forEach(n =>
    if linked->Dict.get(n) != None {
      found->Array.push(`package.json: ${n}, which the root builds not and so needs not`)
    }
  )
  let pnpm = readFileSync(urlIn("pnpm-workspace.yaml", root))
  if !(pnpm->String.includes("\"code/**\"")) {
    found->Array.push("pnpm-workspace.yaml takes not code/**")
  }
  dimension(
    "Workspaces",
    "Does the root's Cargo.toml list every crate beneath code/, its rescript.json and package.json no ReScript package, and pnpm take code/**?",
    found,
    ~notes=[`crates: ${crates->orNone(", ")}`, `ReScript packages: ${names->orNone(", ")}`],
    (),
  )
}
