/**
 * What a repository depending on this model gives it to fill its roles, the JSON file
 * `MONOFLAKE_FILL` names, RFC 8lkuv.
 */
@val external env: Dict.t<string> = "process.env"
@module("node:fs") external read: (string, @as("utf8") _) => string = "readFileSync"

let given: Dict.t<JSON.t> = switch env->Dict.get("MONOFLAKE_FILL") {
| Some(path) if path != "" =>
  JSON.parseOrThrow(read(path))->JSON.Decode.object->Option.getOr(Dict.make())
| _ => Dict.make()
}

/** One part of what was given, read as this model's own type, or none. */
let part: string => option<'a> = key => given->Dict.get(key)->Option.map(Obj.magic)
