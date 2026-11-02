module Contracts = Envelope.Contracts
module Version = Compat.Version

type reported = dict<Version.range>
type description = {versions: option<reported>}

let supported = [
  ("management", Contracts.Interface.Management.version),
  ("deployments", Contracts.Interface.Deployments.version),
]

/**
 * The lowest version control reads of an interface whose current one is given, one behind it and
 * never below 1. One constant until a build declares its own lowest, RFC wnqvu.
 */
let lowestRead = current => Math.Int.max(1, current - 1)

let member = (json, key) => json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(key))

let number = (object, key) =>
  object->Dict.get(key)->Option.flatMap(JSON.Decode.float)->Option.flatMap(Version.make)

/**
 * Only the names control supports are read; any other name is passed over. A value that is no
 * range under any name is refused before this, by the generated reader of the describe answer.
 */
let read = json =>
  switch member(json, "versions") {
  | None => Ok({versions: None})
  | Some(versions) =>
    switch versions->JSON.Decode.object {
    | None => Error("driver interface versions must be an object")
    | Some(versions) =>
      let reported: reported = dict{}
      switch supported->Array.findMap(((name, _)) =>
        switch versions->Dict.get(name) {
        | None => None
        | Some(value) =>
          let range =
            value
            ->JSON.Decode.object
            ->Option.flatMap(o =>
              switch (number(o, "lowest"), number(o, "highest")) {
              | (Some(lowest), Some(highest)) => Version.range(lowest, highest)
              | _ => None
              }
            )
          switch range {
          | None => Some(`driver reported no valid ${name} interface range`)
          | Some(range) =>
            reported->Dict.set(name, range)
            None
          }
        }
      ) {
      | Some(message) => Error(message)
      | None => Ok({versions: Some(reported)})
      }
    }
  }

/** The drivers already warned about, once each per process. Ended by a deferred item. */
let warned: Set.t<string> = Set.make()

let check = (json, ~driver, ~warn=message => Console.warn(message)) =>
  switch read(json) {
  | Error(message) => Error(message)
  | Ok({versions: None}) =>
    if !(warned->Set.has(driver)) {
      warned->Set.add(driver)
      warn(`driver ${driver} reported no interface versions and was let through on first passage`)
    }
    Ok()
  | Ok({versions: Some(versions)}) =>
    let text = (range: Version.range) =>
      `${Float.toString((range.lowest :> float))} to ${Float.toString((range.highest :> float))}`
    switch supported->Array.findMap(((name, current)) =>
      switch (
        versions->Dict.get(name),
        Version.make(Int.toFloat(lowestRead(current))),
        Version.make(Int.toFloat(current)),
      ) {
      | (None, _, _) => Some(`driver reported no valid ${name} interface range`)
      | (Some(driver), Some(lowest), Some(highest)) =>
        switch Version.range(lowest, highest) {
        | None => Some(`control has no valid ${name} interface range`)
        | Some(control) =>
          // Two ranges overlap where some version is read by both, which is where the lowest
          // highest is no lower than either lowest.
          switch Version.written([control, driver]) {
          | Ok(_) => None
          | Error(_) =>
            Some(
              `driver ${name} interface range ${text(
                  driver,
                )} does not overlap control's range ${text(control)}`,
            )
          }
        }
      | (Some(_), _, _) => Some(`control has no valid ${name} interface range`)
      }
    ) {
    | Some(message) => Error(message)
    | None => Ok()
    }
  }

let answer = (json, ~driver) => check(member(json, "data")->Option.getOr(JSON.Null), ~driver)
