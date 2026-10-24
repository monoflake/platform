/**
 * What a repository depending on this model gives it to fill its roles, the JSON file
 * `FILL` names, RFC 8lkuv.
 */
@val external env: Dict.t<string> = "process.env"
@module("node:fs") external read: (string, @as("utf8") _) => string = "readFileSync"

let given: Dict.t<JSON.t> = switch env->Dict.get("FILL") {
| Some(path) if path != "" =>
  JSON.parseOrThrow(read(path))->JSON.Decode.object->Option.getOr(Dict.make())
| _ => Dict.make()
}

/** One part of what was given, read as this model's own type, or none. */
let part: string => option<'a> = key => given->Dict.get(key)->Option.map(Obj.magic)

/**
 * The part filling driver roles, RFC 7ykg6, each by name as `Drivers.driver` has it, with the
 * version of each kind's contract and of `management`, held to `model/ground/drivers.res`.
 */
let drivers = "drivers"

/**
 * The part declaring what a sibling repository's blocks provide, RFC s42ex, each by its main name
 * as `Provided.block` has it.
 */
let provided = "provided"
