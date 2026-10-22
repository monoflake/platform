/**
 * What another repository's model calls to hold its own blocks with this model's code, RFC 7ykg6,
 * given a `Blocks.tree` of `Blocks.held`, by `brief`, `accept`, `check` and `built`.
 */
open Base
open Blocks

type spawned = {status: Nullable.t<int>, stdout: string}
type captured = {cwd: string, encoding: string}
type shown = {cwd: string, stdio: string}
@module("node:child_process")
external capture: (string, array<string>, captured) => spawned = "spawnSync"
@module("node:child_process")
external show: (string, array<string>, shown) => spawned = "spawnSync"
@get external pathname: url => string = "pathname"

let lines = (tree: tree, path, h: held) => {
  let has = (l: lang) => h.languages->Array.includes(l)
  let packages =
    Array.concat(
      has(#rust) ? [`the crate ${h.package}, Cargo.toml`] : [],
      has(#rescript)
        ? [
            `@monoflake/${h.package}, package.json and rescript.json, namespaced ${namespaceOf(
                h.package,
              )}`,
          ]
        : [],
    )
    ->Array.concat(has(#nix) ? ["a NixOS module, default.nix"] : [])
    ->Array.concat(
      has(#docker)
        ? ["an image for each directory, built by Docker for every architecture, docker-bake.hcl"]
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
  let files = filesOf(tree, path)
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
    ...h.released == Some(true)
      ? ["Version: its own, MAJOR.MINOR.PATCH, as it is released"]
      : [`Version: ${unpublished}, as nothing is published`],
    "",
    "Uses, the platform's libraries it may depend on:",
    ...uses == [] ? ["  none"] : uses->Array.map(u => `  ${u}`),
    ...switch h.blocks {
    | Some(named) if named != [] =>
      [
        "Blocks of this tree it may depend on, by their packages:",
        ...named->Array.map(b =>
          `  ${b}${find(tree, b)->Option.mapOr(", no block of it", ((p, _)) => `: ${p}`)}`
        ),
      ]
    | _ => []
    },
    "Takes, the only packages of others its manifests may name, tests' among them:",
    ...takes == [] ? ["  none"] : takes->Array.map(t => `  ${t}`),
    "Samples, what its tests read in every language, as they are:",
    ...h.samples == []
      ? ["  none"]
      : h.samples->Array.map(s =>
          `  ${s}${existsSync(urlIn(s, tree.root)) ? "" : ", not there yet: ask"}`
        ),
    "",
    "The interface, the model's, read and never edited:",
    ...interfaces == []
      ? ["  none written yet: ask for it before writing what implements it"]
      : interfaces->Array.map(f => `  ${path}/${f}`),
    `Yours: every other file under ${path}/, and nothing outside it.`,
    "",
    `Waiting: what an open row leaves undecided is a %todo("<row>") in ReScript or a todo!("<row>")`,
    `in Rust, naming one of: ${tree.rows->Array.join(", ")}.`,
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

/** One block's brief, `brief <package> [--path]`, its directory alone with `--path`. */
let brief = (tree: tree, given: array<string>) =>
  switch given->Array.find(a => !(a->String.startsWith("--"))) {
  | None =>
    Console.error("brief <package>: which block, by its package's name")
    process->setExitCode(2)
  | Some(package) =>
    switch find(tree, package) {
    | None =>
      Console.error(`no block's package is named ${package}`)
      process->setExitCode(2)
    | Some((path, h)) =>
      if given->Array.includes("--path") {
        Console.log(path)
      } else {
        lines(tree, path, h)->Array.forEach(l => Console.log(l))
      }
    }
  }

/** The files changed since `from`, by their paths from the tree's root, or why not. */
let changed = (tree: tree, from) => {
  let run = capture(
    "jj",
    ["diff", "--from", from, "--to", "@", "--name-only"],
    {cwd: tree.root->pathname, encoding: "utf8"},
  )
  switch run.status->Nullable.toOption {
  | Some(0) => Ok(run.stdout->String.split("\n")->Array.filter(l => l != ""))
  | _ => Error(`jj diff --from ${from} answers nothing; is ${from} a revision here?`)
  }
}

/** What a written block breaks of its brief, its directory, samples, interface, tests and todos. */
let problems = (tree: tree, path, h: held) => {
  let found = switch Code.held(tree, path, h) {
  | Some(problems) => problems
  | None => [`${path}: nothing written yet`]
  }
  h.samples->Array.forEach(s =>
    if !existsSync(urlIn(s, tree.root)) {
      found->Array.push(`${s}: a sample the model names, not there`)
    }
  )
  // Its interface is implemented whole, and its tests read every sample, in every language.
  let files = filesOf(tree, path)
  let read = f => readFileSync(urlIn(`${path}/${f}`, tree.root))
  files
  ->Array.filter(f => f->String.endsWith(".resi"))
  ->Array.forEach(f => {
    let implementation = f->String.slice(~start=0, ~end=-1)
    if !(files->Array.includes(implementation)) {
      found->Array.push(`${path}/${f}: no ${implementation} implements it`)
    }
  })
  if files->Array.includes("src/lib.rs") {
    // What a generator writes implements a trait too, so its sources are read beside the block's.
    let writer =
      h.writtenBy
      ->Option.map(w => `code/tools/${w}`)
      ->Option.mapOr([], w =>
        filesOf(tree, w)
        ->Array.filter(f => f->String.endsWith(".rs"))
        ->Array.map(f => readFileSync(urlIn(`${w}/${f}`, tree.root)))
      )
    let rust =
      files
      ->Array.filter(f => f->String.endsWith(".rs") && f != "src/lib.rs")
      ->Array.map(read)
      ->Array.concat(writer)
    let traits = /pub trait (\w+)/g
    let text = read("src/lib.rs")
    let go = ref(true)
    while go.contents {
      switch traits->RegExp.exec(text) {
      | Some(m) =>
        switch m->RegExp.Result.matches {
        | [Some(t)] =>
          // A trait generic over a type is implemented as `impl Bounded<u64> for`, with its
          // argument.
          let implemented = RegExp.fromString(`impl(<[^>]*>)? ${t}(<[^>]*>)? for `)
          if !(rust->Array.some(text => implemented->RegExp.test(text))) {
            found->Array.push(`${path}/src/lib.rs: ${t}, implemented for nothing`)
          }
        | _ => ()
        }
      | None => go := false
      }
    }
  }
  let tests = (l: lang) =>
    files->Array.filter(f =>
      switch l {
      | #rust => f->String.endsWith(".rs") && f != "src/lib.rs"
      | #rescript => f->String.startsWith("tests/") && f->String.endsWith(".res")
      | #nix | #docker => false
      }
    )
  h.languages->Array.forEach(l => {
    let sources = tests(l)->Array.map(read)
    h.samples->Array.forEach(s =>
      if !(sources->Array.some(t => t->String.includes(s))) {
        found->Array.push(`${s}: read by no test in ${languageName(l)}`)
      }
    )
  })
  // A test held back passes a run and holds nothing, so it is a question asked, never an answer.
  h.languages->Array.forEach(l =>
    tests(l)->Array.forEach(f =>
      read(f)
      ->String.split("\n")
      ->Array.forEachWithIndex(
        (line, at) =>
          if /#\[ignore|\b(todo|skip)\s*:|\.(todo|skip)\(/->RegExp.test(line) {
            found->Array.push(`${path}/${f}:${int(at + 1)}: a test held back`)
          },
      )
    )
  )
  todosOf(tree, path)->Array.forEach(((at, row)) =>
    switch row {
    | Some(id) if tree.rows->Array.includes(id) => ()
    | Some(id) => found->Array.push(`${at}: waits on ${id}, which is no open row`)
    | None => found->Array.push(`${at}: a todo naming no row of the checklist`)
    }
  )
  found
}

/** One block held to its brief, `accept <package> [--from <revision>]`, its diff by `--from`. */
let accept = (tree: tree, given: array<string>) => {
  let fromAt = given->Array.findIndex(a => a == "--from")
  let from = fromAt >= 0 ? given->Array.get(fromAt + 1) : None
  let named =
    given->Array.filterWithIndex((a, i) =>
      !(a->String.startsWith("--")) && (fromAt < 0 || i != fromAt + 1)
    )
  switch (named, find(tree, named->Array.get(0)->Option.getOr(""))) {
  | ([], _) =>
    Console.error("accept <package> [--from <revision>]: which block, by its package's name")
    process->setExitCode(2)
  | (_, None) =>
    Console.error(`no block's package is named ${named->Array.join(" ")}`)
    process->setExitCode(2)
  | (_, Some((path, h))) =>
    let found = problems(tree, path, h)
    let notes = switch from {
    | None => [`no --from, so what changed outside ${path}/ is not read`]
    | Some(revision) =>
      switch changed(tree, revision) {
      | Error(why) =>
        found->Array.push(why)
        []
      | Ok(files) =>
        // Workers share one tree, so another block in work changes beside this one, its own.
        let beside =
          tree.blocks
          ->Map.entries
          ->Array.fromIterator
          ->Array.filter(((p, o)) => p != path && tree.work->Dict.get(o.package) == Some(InWork))
          ->Array.map(((p, _)) => `${p}/`)
        let theirs = files->Array.filter(f => beside->Array.some(b => f->String.startsWith(b)))
        files->Array.forEach(f =>
          if f->String.startsWith(`${path}/`) {
            if isInterface(f->String.slice(~start=String.length(path) + 1)) {
              found->Array.push(`${f}: the interface changed, which is the model's`)
            }
          } else if !(theirs->Array.includes(f)) {
            found->Array.push(`${f}: changed, outside ${path}/`)
          }
        )
        [
          `changed since ${revision}: ${int(files->Array.length)} files, ${int(
              theirs->Array.length,
            )} of them another block's in work`,
        ]
      }
    }
    dimension(
      `Accept ${h.name}`,
      `Does ${path} hold what the model asks of it, and change nothing that is not its own?`,
      found,
      ~notes,
      (),
    )
    process->setExitCode(failed.contents ? 1 : 0)
  }
}

/** Every block of a tree held to what it asks, as one dimension. */
let check = (tree: tree, ~title="Blocks held", ~work=?) => {
  let held = Code.hold(tree, ~work?)
  dimension(
    title,
    "Does each written block hold what the model asks of it, and is each in work or accepted?",
    held.found,
    ~notes=[
      `written: ${held.written->orNone(", ")}`,
      `waiting on an open row: ${held.waiting->orNone("; ")}`,
      `not yet written: ${int(held.unwritten)}`,
    ],
    (),
  )
}

/** Every written block built alone by `mise run built <package>` at the tree's root. */
let built = (tree: tree) => {
  let found = []
  tree.blocks->Map.forEachWithKey((h, path) =>
    if Code.held(tree, path, h) != None {
      Console.log(`\n# Built ${h.package}`)
      let run = show(
        "mise",
        ["run", "built", h.package],
        {cwd: tree.root->pathname, stdio: "inherit"},
      )
      if run.status->Nullable.toOption != Some(0) {
        let failing = `${h.package}: mise run built ${h.package} fails`
        tree.work->Dict.get(h.package) == Some(InWork)
          ? inWork->Array.push(failing)
          : found->Array.push(failing)
      }
    }
  )
  dimension(
    "Blocks",
    "Does every written block build, format, lint and pass its tests alone?",
    found,
    (),
  )
  shownInWork()
  process->setExitCode(failed.contents ? 1 : 0)
}
