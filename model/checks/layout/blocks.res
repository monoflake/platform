/**
 * Every block the model asks code of, by the directory it lies in, RFC fhg6w. `code.res` holds the
 * code to them, and `tree.res` briefs and accepts one, of this repository or another's.
 */
open Base

/** A block's language, Rust or ReScript for code, Nix for a system and Docker for an image. */
type lang = [#rust | #rescript | #nix | #docker]

/**
 * What a directory is to hold, of the model and in which languages, its package name, the libraries
 * it may use and its samples.
 */
type held = {
  name: string,
  languages: array<lang>,
  package: string,
  license: string,
  uses: array<string>,
  takes: array<Libraries.taken>,
  samples: array<string>,
  /** The tool writing its sources, by its package's name, which its crate builds by. */
  writtenBy?: string,
}

/** The directory each layer's components lie in. */
let group = layer =>
  switch layer {
  | 1 => Some("apps")
  | 0 => Some("products")
  | -1 => Some("primitives")
  | -2 => Some("substrate")
  | -3 => Some("platform")
  | _ => None
  }

/** A half in a name is the layer's already, so it is no part of the directory's. */
let dirName = name => name->String.replace("(organization)", "")->String.replace("(platform)", "")

/**
 * A package's name is the model's, what is in parentheses after a hyphen, `control-organization`.
 */
let packageName = name => name->String.replace("(", "-")->String.replace(")", "")

/** A library's name in the model carries a mark, which its directory does not. */
let libraryDir = name => name->String.replace("*", "")

let languageName = (l: [< lang]) =>
  switch l {
  | #rust => "rust"
  | #rescript => "rescript"
  | #nix => "nix"
  | #docker => "docker"
  }

/**
 * A ReScript package's namespace, its package's name in upper camel case, `envelope-generator` as
 * `EnvelopeGenerator`, the workspace's `docs/naming.md`.
 */
let namespaceOf = package =>
  package
  ->String.split("-")
  ->Array.map(w => w->String.charAt(0)->String.toUpperCase ++ w->String.slice(~start=1))
  ->Array.join("")

/**
 * Every block by its directory, what the model asks of them that it cannot give, and the components
 * whose code is not the platform's.
 */
let expected = () => {
  let found = []
  let expected: Map.t<string, held> = Map.make()
  let none = []
  designed->Array.forEach(((name, c)) =>
    switch c.language {
    | _ if Components.elsewhere(name) => ()
    | None => none->Array.push(name)
    | Some(language) =>
      switch group(c.layer) {
      | None =>
        found->Array.push(
          `${name}: written in a language, yet layer ${int(c.layer)} has no directory`,
        )
      | Some(g) =>
        expected->Map.set(
          `code/${g}/${dirName(name)}`,
          {
            name,
            languages: [(language :> lang)],
            package: packageName(name),
            license: Components.permissive,
            uses: c.uses,
            takes: c.takes->Option.getOr([]),
            samples: c.samples->Option.getOr([]),
          },
        )
      }
      c.uses->Array.forEach(u =>
        switch Libraries.libraries->Dict.get(u) {
        | Some(l) if !(l.languages->Array.includes(language)) =>
          found->Array.push(
            `${name} uses ${u}, of ${l.languages
              ->Array.map(languageName)
              ->Array.join(" and ")}, not ${languageName(language)}`,
          )
        | _ => ()
        }
      )
    }
  )
  Libraries.libraries->Dict.forEachWithKey((l, name) =>
    expected->Map.set(
      `code/libs/${libraryDir(name)}`,
      {
        name,
        languages: l.languages->Array.map(l => (l :> lang)),
        package: libraryDir(name),
        license: Components.permissive,
        uses: l.uses,
        takes: l.takes->Option.getOr([]),
        samples: l.samples->Option.getOr([]),
        writtenBy: ?Tools.writerOf(name),
      },
    )
  )
  Tools.tools->Dict.forEachWithKey((t, name) =>
    expected->Map.set(
      `code/tools/${name}`,
      {
        name,
        languages: t.languages->Array.map(l => (l :> lang)),
        package: name,
        license: Components.permissive,
        uses: t.uses->Option.getOr([]),
        takes: t.takes->Option.getOr([]),
        samples: t.samples->Option.getOr([]),
      },
    )
  )
  (expected, found, none)
}

/**
 * What every ReScript package sets, warning 4 on and every warning an error but 110, a `%todo`,
 * `docs/code.md`.
 */
let rescriptWarnings = ("+4", "+a-110")

/** What every ReScript package writes beside its sources, an ES module by this suffix. */
let rescriptOutput = ("esmodule", ".res.mjs")

/** The version every package holds while none is published, decided by the author on 2026-10-20. */
let unpublished = "0.0.0"

/**
 * The lints the root's `Cargo.toml` sets for every crate, Rust's and Clippy's, each denied or
 * forbidden, `docs/code.md`.
 */
let rustLints = [("unsafe_code", "forbid"), ("missing_docs", "deny")]
let clippyLints = [
  "unwrap_used",
  "expect_used",
  "panic",
  "indexing_slicing",
  "as_conversions",
  "unimplemented",
  "wildcard_enum_match_arm",
  "dbg_macro",
]

/**
 * A repository whose blocks this model's code holds, its root, each block by its directory from
 * there, each written block's state and the rows a todo may name, RFC 7ykg6.
 */
type tree = {root: url, blocks: Map.t<string, held>, work: dict<Work.state>, rows: array<string>}

/** Every open row of the checklist, the one thing a `%todo` or a `todo!` may name. */
let openRows = () => Checklist.checklist->Array.filter(i => i.done == None)->Array.map(i => i.id)

/** This repository's own blocks. */
let own = () => {
  let (blocks, _, _) = expected()
  {root, blocks, work: Work.blocks, rows: openRows()}
}

/** A block by its package's name, as a brief and an acceptance each name one. */
let find = (tree, package) =>
  tree.blocks->Map.entries->Array.fromIterator->Array.find(((_, h)) => h.package == package)

/**
 * Whether a file of a block is its interface, the model's to write, a crate's root, its build
 * script or a `.resi`.
 */
let isInterface = file =>
  file->String.endsWith(".resi") || file == "src/lib.rs" || file == "build.rs"

/**
 * Whether a file of a block may cross into JavaScript unchecked, its own or its tests' bindings.
 */
let isBinding = file =>
  file->String.startsWith("src/bindings/") || file->String.startsWith("tests/bindings/")

/** Every file a block holds, by its path within it, what a build writes passed over. */
let filesOf = (tree, path) => {
  let skipped = ["node_modules", "target", "lib", "dist", "generated"]
  let rec walk = inner =>
    entries(urlIn(`${path}/${inner}`, tree.root), {withFileTypes: true})->Array.flatMap(e => {
      let name = inner ++ e->entryName
      if e->isDirectory {
        skipped->Array.includes(e->entryName) ? [] : walk(`${name}/`)
      } else if name->String.endsWith(".res.mjs") {
        []
      } else {
        [name]
      }
    })
  existsSync(urlIn(`${path}/`, tree.root)) ? walk("") : []
}

/** Each `%todo` and `todo!` of a block's sources by file and line, with the row it names. */
let todosOf = (tree, path) =>
  filesOf(tree, path)
  ->Array.filter(f => f->String.endsWith(".res") || f->String.endsWith(".rs"))
  ->Array.flatMap(f =>
    readFileSync(urlIn(`${path}/${f}`, tree.root))
    ->String.split("\n")
    ->Array.flatMapWithIndex((line, at) =>
      switch /(%todo|todo!)(\(\s*"([^"]*)"\s*\))?/->RegExp.exec(line) {
      | Some(m) =>
        let named = switch m->RegExp.Result.matches {
        | [_, _, Some(id)] => Some(id)
        | _ => None
        }
        [(`${path}/${f}:${int(at + 1)}`, named)]
      | None => []
      }
    )
  )

/** Where a block's sources cross into JavaScript unchecked outside `src/bindings/`. */
let unboundOf = (tree, path) =>
  filesOf(tree, path)
  ->Array.filter(f => (f->String.endsWith(".res") || f->String.endsWith(".resi")) && !isBinding(f))
  ->Array.flatMap(f =>
    readFileSync(urlIn(`${path}/${f}`, tree.root))
    ->String.split("\n")
    ->Array.flatMapWithIndex((line, at) =>
      /%%?raw\b|\bObj\.magic\b|^\s*(@[^\n]*\s)?external\s/->RegExp.test(line)
        ? [`${path}/${f}:${int(at + 1)}: crosses into JavaScript unchecked outside its bindings`]
        : []
    )
  )
