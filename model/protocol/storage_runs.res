/**
 * The storage's runs out of TLC's output, `node storage_runs.res.mjs <output>`: each run that ended
 * on its own once, one JSON object a line sorted by its text, which storage's replay test reads.
 */
@module("node:fs") external readText: (string, string) => string = "readFileSync"
@val external argv: array<string> = "process.argv"

/** The value after a name in a row TLC printed, up to the next space or quote. */
let field = (line, name) =>
  switch RegExp.fromString(` ${name}=([^ "]*)`)->RegExp.exec(line) {
  | Some(found) =>
    found->RegExp.Result.matches->Array.get(0)->Option.flatMap(x => x)->Option.getOr("")
  | None => ""
  }

let items = text =>
  switch text {
  | "" => []
  | text => text->String.split(",")
  }

let quoted = text => `"${text}"`

/** A list of `key:value` items as a JSON object, an underscore read as a space where spaced. */
let pairs = (text, ~spaced) =>
  items(text)
  ->Array.map(item =>
    switch item->String.indexOf(":") {
    | -1 => `${quoted(item)}:""`
    | at =>
      let value = item->String.slice(~start=at + 1)
      let value = spaced ? value->String.replaceAll("_", " ") : value
      `${quoted(item->String.slice(~start=0, ~end=at))}:${quoted(value)}`
    }
  )
  ->Array.join(",")

/** A run row as TLC printed it, held as one run of the fixture. */
let runOf = line => {
  let list = name => items(field(line, name))->Array.map(quoted)->Array.join(",")
  let content = field(line, "content") == "1" ? "true" : "false"
  `{"case":{"actors":{${pairs(field(line, "actors"), ~spaced=true)}}},"steps":[${list(
      "steps",
    )}],"end":{"content":${content},"names":[${list("names")}],"reads":{${pairs(
      field(line, "reads"),
      ~spaced=false,
    )}}}}`
}

let fixtureOf = out => {
  let rows =
    out
    ->String.split("\n")
    ->Array.filter(line => line->String.includes("run actors="))
    ->Array.map(runOf)
  let runs = Set.fromArray(rows)->Set.values->Array.fromIterator->Array.toSorted(String.compare)
  runs->Array.join("\n")
}

Console.log(fixtureOf(readText(argv->Array.getUnsafe(2), "utf8")))
