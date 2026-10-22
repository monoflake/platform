/*** The samples read as they stand from their paths, JSON through `JSON.Decode`. */
module Contracts = Envelope.Contracts

/** The sample at `path`, from the repository's root. */
let read = path => Node.readFileSync(Node.fromRoot(path))->JSON.parseOrThrow

/** A member of a JSON object, if it is one and has it. */
let member = (json, name) => json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(name))

/** A member that must be there, by a path of names. */
let at = (json, names) =>
  names->Array.reduce(json, (json, name) =>
    switch member(json, name) {
    | Some(value) => value
    | None => JsError.throwWithMessage(`no ${name} in ${JSON.stringify(json)}`)
    }
  )

let string = json =>
  switch json->JSON.Decode.string {
  | Some(text) => text
  | None => JsError.throwWithMessage(`${JSON.stringify(json)}: no string`)
  }

let items = json =>
  switch json->JSON.Decode.array {
  | Some(items) => items
  | None => JsError.throwWithMessage(`${JSON.stringify(json)}: no array`)
  }

/** A value read by envelope*, which the sample must hold as its type writes it. */
let decoded = (json, fromJson: JSON.t => result<'a, Envelope.Malformed.t>) =>
  switch fromJson(json) {
  | Ok(value) => value
  | Error(_) => JsError.throwWithMessage(`${JSON.stringify(json)}: not as its type writes it`)
  }

let runs = json => json->decoded(Contracts.DeploymentRuns.fromJson)

let failure = json => json->decoded(Contracts.Failure.fromJson)

/** The name a placeholder `{"$capture": name}` or `{"$use": name}` gives, if it is one. */
let placeholder = (json, kind) => member(json, kind)->Option.map(string)
