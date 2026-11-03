/*** Block selection and the dimension's assumption output. */
open Testing

type console
@val external console: console = "console"
@get external log: console => string => unit = "log"
@set external setLog: (console, string => unit) => unit = "log"

let capture = run => {
  let original = console->log
  let failed = Base.failed.contents
  let output = []
  console->setLog(line => output->Array.push(line))
  let restore = () => {
    console->setLog(original)
    Base.failed := failed
    Base.process->Base.setExitCode(0)
  }
  try {
    run()
    restore()
    output->Array.join("\n")
  } catch {
  | error =>
    restore()
    throw(error)
  }
}

let tree = Blocks.own()
let written = []
tree.blocks->Map.forEachWithKey((held, path) => {
  if Code.held(tree, path, held) != None {
    written->Array.push(held.package)
  }
})

let build = packages => {
  let ran = []
  let output = capture(() =>
    Tree.built(tree, ~packages, ~run=(_, arguments, _) => {
      ran->Array.push(arguments->Array.get(2)->Option.getOr(""))
      {Tree.status: Nullable.fromOption(Some(0)), stdout: ""}
    })
  )
  (ran, output)
}

test("built runs only the two named written packages", () => {
  deepEqual(written->Array.length >= 3, true)
  let packages = written->Array.slice(~start=0, ~end=2)
  let (ran, _) = build(packages)
  deepEqual(ran, packages)
})

test("built runs every written package without a selection", () => {
  let (ran, _) = build([])
  deepEqual(ran, written)
})

test("built reports an unknown package as a Blocks violation", () => {
  let (ran, output) = build(["missing-checkflags-package"])
  deepEqual(ran, [])
  deepEqual(output->String.includes("# Blocks"), true)
  deepEqual(output->String.includes("  x missing-checkflags-package:"), true)
})

test("dimension summarizes assumes without notes and prints them with notes", () => {
  let original = Base.args->Array.copy
  Base.args
  ->Array.splice(
    ~start=0,
    ~remove=Base.args->Array.length,
    ~insert=original->Array.filter(argument => argument != "--notes"),
  )
  ->ignore
  let render = () =>
    capture(() =>
      Base.dimension("Example", "Question", [], ~notes=["plain"], ~assumed=["detail"], ())
    )
  let without = render()
  Base.args->Array.push("--notes")
  let withNotes = render()
  Base.args->Array.splice(~start=0, ~remove=Base.args->Array.length, ~insert=original)
  deepEqual(without->String.includes("  ~ detail"), false)
  deepEqual(without->String.includes("  ~ 1 assumes, shown with --notes"), true)
  deepEqual(without->String.includes("  plain"), true)
  deepEqual(withNotes->String.includes("  ~ detail"), true)
  let empty = capture(() => Base.dimension("Empty", "Question", [], ()))
  deepEqual(empty->String.includes("  ~"), false)
})
