/**
 * One block held to its brief, its model half, `mise run accept <package> [--from <revision>]`:
 * what the model asks of its directory, as `code.res` holds every one; its samples there; each todo
 * naming an open row; nothing crossing into JavaScript unchecked outside its bindings; and, from
 * the revision its work began at, no change outside its directory but another in work, nor to its
 * interface, the conversation's to run as it reads the diff, since a worker runs no jj. Its
 * languages' builds, lints and tests are the task's to run after, in order, `docs/code.md`.
 */
open Base
open Blocks

type spawned = {status: Nullable.t<int>, stdout: string}
type options = {cwd: string, encoding: string}
@module("node:child_process")
external spawnSync: (string, array<string>, options) => spawned = "spawnSync"
@get external pathname: url => string = "pathname"

/** The files changed since `from`, by their paths from the repository's root, or why not. */
let changed = from => {
  let run = spawnSync(
    "jj",
    ["diff", "--from", from, "--to", "@", "--name-only"],
    {cwd: root->pathname, encoding: "utf8"},
  )
  switch run.status->Nullable.toOption {
  | Some(0) => Ok(run.stdout->String.split("\n")->Array.filter(l => l != ""))
  | _ => Error(`jj diff --from ${from} answers nothing; is ${from} a revision here?`)
  }
}

let given = args->Array.slice(~start=2)
let fromAt = given->Array.findIndex(a => a == "--from")
let from = fromAt >= 0 ? given->Array.get(fromAt + 1) : None
let named =
  given->Array.filterWithIndex((a, i) =>
    !(a->String.startsWith("--")) && (fromAt < 0 || i != fromAt + 1)
  )

switch (named, find(named->Array.get(0)->Option.getOr(""))) {
| ([], _) =>
  Console.error("accept <package> [--from <revision>]: which block, by its package's name")
  process->setExitCode(2)
| (_, None) =>
  Console.error(`no block's package is named ${named->Array.join(" ")}`)
  process->setExitCode(2)
| (_, Some((path, h))) =>
  let found = switch Code.held(path, h) {
  | Some(problems) => problems
  | None => [`${path}: nothing written yet`]
  }
  h.samples->Array.forEach(s =>
    if !existsSync(urlIn(s, root)) {
      found->Array.push(`${s}: a sample the model names, not there`)
    }
  )
  // Its interface is implemented whole, and its tests read every sample, in every language.
  let files = filesOf(path)
  let read = f => readFileSync(urlIn(`${path}/${f}`, root))
  files
  ->Array.filter(f => f->String.endsWith(".resi"))
  ->Array.forEach(f => {
    let implementation = f->String.slice(~start=0, ~end=-1)
    if !(files->Array.includes(implementation)) {
      found->Array.push(`${path}/${f}: no ${implementation} implements it`)
    }
  })
  if files->Array.includes("src/interface.rs") {
    let rust = files->Array.filter(f => f->String.endsWith(".rs") && f != "src/interface.rs")
    let traits = /pub trait (\w+)/g
    let text = read("src/interface.rs")
    let go = ref(true)
    while go.contents {
      switch traits->RegExp.exec(text) {
      | Some(m) =>
        switch m->RegExp.Result.matches {
        | [Some(t)] =>
          if !(rust->Array.some(f => read(f)->String.includes(`impl ${t} for`))) {
            found->Array.push(`${path}/src/interface.rs: ${t}, implemented for nothing`)
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
      | #rust => f->String.endsWith(".rs") && f != "src/interface.rs"
      | #rescript => f->String.startsWith("tests/") && f->String.endsWith(".res")
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
  let rows = openRows()
  todosOf(path)->Array.forEach(((at, row)) =>
    switch row {
    | Some(id) if rows->Array.includes(id) => ()
    | Some(id) => found->Array.push(`${at}: waits on ${id}, which is no open row`)
    | None => found->Array.push(`${at}: a todo naming no row of the checklist`)
    }
  )
  let notes = switch from {
  | None => [`no --from, so what changed outside ${path}/ is not read`]
  | Some(revision) =>
    switch changed(revision) {
    | Error(why) =>
      found->Array.push(why)
      []
    | Ok(files) =>
      // Workers share one tree, so another block in work changes beside this one, its own to hold.
      let (blocks, _, _) = Blocks.expected()
      let beside =
        blocks
        ->Map.entries
        ->Array.fromIterator
        ->Array.filter(((p, o)) => p != path && Work.blocks->Dict.get(o.package) == Some(InWork))
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
