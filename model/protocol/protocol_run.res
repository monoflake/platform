/**
 * TLC over each specification, `mise run protocol`: every switch off must pass, each defect's
 * switch must break its property, and its table must match what control's tests read, RFC w0w82.
 */
type bytes
type spawned = {status: Null.t<int>, stdout: string, stderr: string}
type spawnOptions = {cwd?: string, encoding: string, maxBuffer: int}
type mkdirOptions = {recursive: bool}
type rmOptions = {recursive: bool, force: bool}

@module("node:child_process")
external spawnSync: (string, array<string>, spawnOptions) => spawned = "spawnSync"
@module("node:fs") external readText: (string, string) => string = "readFileSync"
@module("node:fs") external readBytes: string => bytes = "readFileSync"
@module("node:fs") external writeText: (string, string) => unit = "writeFileSync"
@module("node:fs") external existsSync: string => bool = "existsSync"
@module("node:fs") external mkdirSync: (string, mkdirOptions) => unit = "mkdirSync"
@module("node:fs") external mkdtempSync: string => string = "mkdtempSync"
@module("node:fs") external rmSync: (string, rmOptions) => unit = "rmSync"
@module("node:os") external homedir: unit => string = "homedir"
@module("node:os") external tmpdir: unit => string = "tmpdir"
type hash
@module("node:crypto") external createHash: string => hash = "createHash"
@send external update: (hash, bytes) => hash = "update"
@send external digest: (hash, string) => string = "digest"
@val external argv: array<string> = "process.argv"
@val external exitWith: int => unit = "process.exit"

let release = "v1.7.4"
let sha256 = "936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88"
let megabytes = 1024 * 1024 * 512
let directory = "model/protocol"

type expected = Invariant(string) | Property(string)
type defect = {flag: string, breaks: expected}
type spec = {name: string, defects: array<defect>}

let specs = [
  {
    name: "overlap",
    defects: [
      {flag: "EXACT_RANGE", breaks: Invariant("NoStuckDeploy")},
      {flag: "DRIVER_OWN_VERSION_ONLY", breaks: Invariant("NoStuckDeploy")},
      {flag: "TWO_BEHIND", breaks: Invariant("NoStuckDeploy")},
    ],
  },
]

/** The release's jar in a cache outside the tree, taken once and refused on a different hash. */
let jar = () => {
  let cache = `${homedir()}/.cache/tlaplus/${release}`
  let file = `${cache}/tla2tools.jar`
  if !existsSync(file) {
    mkdirSync(cache, {recursive: true})
    let url = `https://github.com/tlaplus/tlaplus/releases/download/${release}/tla2tools.jar`
    ignore(spawnSync("curl", ["-fsSL", "-o", file, url], {encoding: "utf8", maxBuffer: megabytes}))
  }
  let found = existsSync(file) ? createHash("sha256")->update(readBytes(file))->digest("hex") : ""
  if found != sha256 {
    Console.error(`tla2tools.jar at ${file} hashes to ${found}, not ${sha256}`)
    exitWith(1)
  }
  file
}

/** TLC in a directory of its own, as it writes its states beside the specification it reads. */
let tlc = (~tools, ~name, ~config, ~workers) => {
  let place = mkdtempSync(`${tmpdir()}/protocol-`)
  writeText(`${place}/${name}.tla`, readText(`${directory}/${name}.tla`, "utf8"))
  writeText(`${place}/${name}.cfg`, config)
  let started = Date.now()
  let run = spawnSync(
    "java",
    [
      "-XX:+UseParallelGC",
      "-cp",
      tools,
      "tlc2.TLC",
      "-lncheck",
      "final",
      "-workers",
      workers,
      "-config",
      `${name}.cfg`,
      name,
    ],
    {cwd: place, encoding: "utf8", maxBuffer: megabytes},
  )
  rmSync(place, {recursive: true, force: true})
  (run.stdout, (Date.now() -. started) /. 1000.)
}

/** The checked sections of a configuration replaced by what is asked. */
let asking = (config, checked) => {
  let lines = config->String.split("\n")
  let from = lines->Array.findIndex(l => l == "INVARIANTS")
  let upto = lines->Array.findIndex(l => l->String.startsWith("CHECK_DEADLOCK"))
  [
    ...lines->Array.slice(~start=0, ~end=from),
    checked,
    ...lines->Array.slice(~start=upto),
  ]->Array.join("\n")
}

let distinct = out =>
  switch /, ([0-9]+) distinct states found, /->RegExp.exec(out) {
  | Some(found) =>
    found->RegExp.Result.matches->Array.get(0)->Option.flatMap(x => x)->Option.getOr("?")
  | None => "?"
  }

let passed = out => out->String.includes("Model checking completed. No error has been found.")

let broke = (out, breaks) =>
  switch breaks {
  | Invariant(name) => out->String.includes(`Invariant ${name} is violated`)
  | Property(name) =>
    out->String.includes(`Action property ${name} is violated`) ||
    out->String.includes(`Temporal properties were violated`) ||
    out->String.includes(`Error: The action of property ${name}`)
  }

/** The shortest trace of a broken run, each step's action name alone. */
let trace = out =>
  out
  ->String.split("\n")
  ->Array.filterMap(line =>
    switch /^State [0-9]+: <([A-Za-z]+)/->RegExp.exec(line) {
    | Some(found) => found->RegExp.Result.matches->Array.get(0)->Option.flatMap(x => x)
    | None => None
    }
  )
  ->Array.join(" ")

/** A row as TLC printed it, a JSON object once its prefix is gone. */
let rowOf = line =>
  line->String.replaceAll("\\\"", "\"")->String.split("row ")->Array.at(-1)->Option.getOr("")

/** The table TLC exports, which control's tests read, each row once in a stable order. */
let tableOf = (~tools, ~name, ~config) => {
  let (out, _) = tlc(~tools, ~name, ~config=asking(config, "INVARIANT\n\tTable"), ~workers="1")
  let rows =
    out
    ->String.split("\n")
    ->Array.filter(line => line->String.includes("row {"))
    ->Array.map(line => rowOf(line)->String.replaceAll("}\"", "}"))
    ->Array.toSorted(String.compare)
  `[\n${rows->Array.join(",\n")}\n]\n`
}

let write = argv->Array.includes("--write")
let tools = jar()
let failures = ref(0)
let failed = why => {
  Console.log(`FAIL ${why}`)
  failures := failures.contents + 1
}

/** Two tables as data, so a formatter rewriting the file is no drift. */
let same = (a, b) => JSON.stringify(JSON.parseOrThrow(a)) == JSON.stringify(JSON.parseOrThrow(b))

specs->Array.forEach(spec => {
  let config = readText(`${directory}/${spec.name}.cfg`, "utf8")
  let (out, seconds) = tlc(~tools, ~name=spec.name, ~config, ~workers="auto")
  if passed(out) {
    Console.log(
      `${spec.name}: passed, ${distinct(out)} distinct states, ${Float.toString(seconds)}s`,
    )
  } else {
    failed(`${spec.name}: every switch off did not pass\n${out}`)
  }
  spec.defects->Array.forEach(({flag, breaks}) => {
    let checked = switch breaks {
    | Invariant(name) => `INVARIANT\n\t${name}`
    | Property(name) => `PROPERTY\n\t${name}`
    }
    let on =
      config
      ->String.replace(`${flag} = FALSE`, `${flag} = TRUE`)
      ->asking(checked)
    let (out, seconds) = tlc(~tools, ~name=spec.name, ~config=on, ~workers="auto")
    if broke(out, breaks) {
      Console.log(
        `${spec.name} ${flag}: broke as it must, ${distinct(out)} distinct states, ${Float.toString(
            seconds,
          )}s, ${trace(out)}`,
      )
    } else {
      failed(`${spec.name} ${flag}: did not break\n${out}`)
    }
  })
  let file = `${directory}/${spec.name}-table.json`
  let table = tableOf(~tools, ~name=spec.name, ~config)
  if write {
    writeText(file, table)
    Console.log(`${file} written`)
  } else if !existsSync(file) || same(readText(file, "utf8"), table) == false {
    failed(`${file} differs from what TLC decides, \`mise run protocol --write\` writes it`)
  } else {
    Console.log(`${file} matches what TLC decides`)
  }
})
if failures.contents > 0 {
  exitWith(1)
}
