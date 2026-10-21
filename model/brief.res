/**
 * One block's brief, `mise run brief <package> [--path]`: everything a worker needs to write it,
 * read from the model, so no brief is written by hand and none drifts from what is checked,
 * `docs/code.md`. With `--path`, its directory alone, for the tasks that run in it.
 */
open Base
open Blocks

let crate = (h: held) => h.package
let scoped = (h: held) => `@monoflake/${h.package}`

let lines = (path, h: held) => {
  let has = (l: lang) => h.languages->Array.includes(l)
  let packages = Array.concat(
    has(#rust) ? [`the crate ${crate(h)}, Cargo.toml`] : [],
    has(#rescript)
      ? [`${scoped(h)}, package.json and rescript.json, namespaced ${namespaceOf(h.package)}`]
      : [],
  )
  let uses = h.uses->Array.map(u => {
    let dir = libraryDir(u)
    `${u}: code/libs/${dir}, ${h.languages
      ->Array.map(l => l == #rust ? `the crate ${dir}` : `@monoflake/${dir}`)
      ->Array.join(" or ")}`
  })
  let takes =
    h.takes->Array.map(t => `${languageName(t.language)}: ${t.name}, major version ${t.major}`)
  let files = filesOf(path)
  let interfaces = files->Array.filter(isInterface)
  let tool = Tools.tools->Dict.get(h.name)
  let what = switch Libraries.libraries->Dict.get(h.name) {
  | Some(l) => Some(l.what)
  | None => tool->Option.map(t => t.what)
  }
  let generation = switch (h.writtenBy, tool->Option.flatMap(t => t.writes)) {
  | (Some(w), _) => [`Written by: ${w}, its Rust by build.rs and its ReScript by mise run generate`]
  | (None, Some(l)) => [`Writes: ${l}'s sources, as model/graph/tools.res says`]
  | (None, None) => []
  }
  [
    `# Brief: ${h.name}`,
    "",
    `Directory: ${path}`,
    ...what->Option.mapOr([], w => [`What: ${w}`]),
    ...generation,
    `Languages: ${h.languages->Array.map(languageName)->Array.join(", ")}`,
    `Packages: ${packages->Array.join("; ")}; license ${h.license}`,
    "",
    "Uses, the platform's libraries it may depend on:",
    ...uses == [] ? ["  none"] : uses->Array.map(u => `  ${u}`),
    "Takes, the only packages of others its manifests may name, tests' among them:",
    ...takes == [] ? ["  none"] : takes->Array.map(t => `  ${t}`),
    "Samples, what its tests read in every language, as they are:",
    ...h.samples == []
      ? ["  none"]
      : h.samples->Array.map(s =>
          `  ${s}${existsSync(urlIn(s, root)) ? "" : ", not there yet: ask"}`
        ),
    "",
    "The interface, the model's, read and never edited:",
    ...interfaces == []
      ? ["  none written yet: ask for it before writing what implements it"]
      : interfaces->Array.map(f => `  ${path}/${f}`),
    `Yours: every other file under ${path}/, and nothing outside it.`,
    "",
    `Waiting: what an open row leaves undecided is a %todo("<row>") in ReScript or a todo!("<row>")`,
    `in Rust, naming one of: ${openRows()->Array.join(", ")}.`,
    "",
    "Read first: the workspace's AGENTS.md and docs/lessons.md, this repository's AGENTS.md, and",
    "docs/code.md, how code is written here.",
    "",
    `Done when \`mise run accept ${h.package}\` passes at this repository's root. It holds this`,
    "block alone; the whole is the conversation's to hold, and so is what changed since you began,",
    "which it reads with jj as you report: run no jj yourself.",
    "",
    "Other blocks may be in work beside you in this tree. Touch none of them; a failure of theirs is",
    "not yours, and none of it fails your acceptance.",
    "",
    "Ask, never change: anything under model/, tests/, vendor/ or docs/, an interface file, a",
    "manifest at the root, or a rule that seems wrong. Report it and stop on that point.",
  ]
}

let given = args->Array.slice(~start=2)
switch given->Array.find(a => !(a->String.startsWith("--"))) {
| None =>
  Console.error("brief <package>: which block, by its package's name")
  process->setExitCode(2)
| Some(package) =>
  switch find(package) {
  | None =>
    Console.error(`no block's package is named ${package}`)
    process->setExitCode(2)
  | Some((path, h)) =>
    if given->Array.includes("--path") {
      Console.log(path)
    } else {
      lines(path, h)->Array.forEach(l => Console.log(l))
    }
  }
}
