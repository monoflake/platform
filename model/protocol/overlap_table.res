/**
 * The overlap table out of TLC's output, `node overlap_table.res.mjs <output>`: each row once in
 * a stable order, which control's tests read, RFC w0w82.
 */
@module("node:fs") external readText: (string, string) => string = "readFileSync"
@val external argv: array<string> = "process.argv"

/** A row as TLC printed it, a JSON object once its prefix is gone. */
let rowOf = line =>
  line->String.replaceAll("\\\"", "\"")->String.split("row ")->Array.at(-1)->Option.getOr("")

/** The table TLC exports, which control's tests read, each row once in a stable order. */
let tableOf = out => {
  let rows =
    out
    ->String.split("\n")
    ->Array.filter(line => line->String.includes("row {"))
    ->Array.map(line => rowOf(line)->String.replaceAll("}\"", "}"))
    ->Array.toSorted(String.compare)
  `[\n${rows->Array.join(",\n")}\n]\n`
}

Console.log(tableOf(readText(argv->Array.getUnsafe(2), "utf8"))->String.trimEnd)
