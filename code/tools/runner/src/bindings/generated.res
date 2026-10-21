/***
 * Every interface's operations as `Envelope.Contracts.Interface` holds them, read as data.
 * Deferred, the workspace's `envelope-operations-table`.
 */
@module("@monoflake/envelope/generated/contracts.res.mjs")
external interfaces: dict<dict<JSON.t>> = "Interface"

let field = (o, name) => o->Dict.get(name)->Option.flatMap(JSON.Decode.string)

/** An operation's output type by its interface and its name, as the model writes them. */
let outputs: dict<string> = Dict.fromArray(
  interfaces
  ->Dict.valuesToArray
  ->Array.flatMap(values =>
    values
    ->Dict.valuesToArray
    ->Array.filterMap(JSON.Decode.object)
    ->Array.filterMap(o =>
      switch (field(o, "interface"), field(o, "name"), field(o, "output")) {
      | (Some(i), Some(name), Some(output)) => Some((`${i}/${name}`, output))
      | (Some(_) | None, Some(_) | None, Some(_) | None) => None
      }
    )
  ),
)
