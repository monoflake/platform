/**
 * What a repository depending on this model gives it to fill its roles, RFC 8lkuv: the JSON file
 * `MONOFLAKE_FILL` names, its `components`, `records` and `kept` joined to this model's own. With
 * none, this model is checked alone, each role an assumption on its contract.
 */
@val external env: Dict.t<string> = "process.env"
@module("node:fs") external read: (string, @as("utf8") _) => string = "readFileSync"

let given: Dict.t<JSON.t> = switch env->Dict.get("MONOFLAKE_FILL") {
| Some(path) if path != "" =>
  switch JSON.parseOrThrow(read(path)) {
  | Object(parts) => parts
  | _ => Dict.make()
  }
| _ => Dict.make()
}

/** One part of what was given, read as this model's own type, or none. */
let part: string => option<'a> = key => given->Dict.get(key)->Option.map(Obj.magic)
