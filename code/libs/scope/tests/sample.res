/*** The samples read as they stand from their paths, JSON through `JSON.Decode`. */
module Contracts = Envelope.Contracts
module Needs = Vocabulary.Needs

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

let number = json =>
  switch json->JSON.Decode.float {
  | Some(n) => n
  | None => JsError.throwWithMessage(`${JSON.stringify(json)}: no number`)
  }

let items = json =>
  switch json->JSON.Decode.array {
  | Some(items) => items
  | None => JsError.throwWithMessage(`${JSON.stringify(json)}: no array`)
  }

let object = json =>
  switch json->JSON.Decode.object {
  | Some(o) => o
  | None => JsError.throwWithMessage(`${JSON.stringify(json)}: no object`)
  }

/** A type read by envelope*, which the sample must hold as that type writes it. */
let decoded = (json, fromJson: JSON.t => result<'a, Envelope.Malformed.t>) =>
  switch fromJson(json) {
  | Ok(value) => value
  | Error(_) => JsError.throwWithMessage(`${JSON.stringify(json)}: not as its type writes it`)
  }

/** The bytes a sample spells in hex. */
let hex = json =>
  switch json->string->Envelope.Hex.decode {
  | Some(bytes) => bytes
  | None => JsError.throwWithMessage(`${JSON.stringify(json)}: no hex`)
  }

/** An issuer section as JSON, written to the CBOR a bundle carries. */
let section = json =>
  switch json
  ->decoded(Contracts.BundleIssuer.fromJson)
  ->Contracts.BundleIssuer.toCbor
  ->Codec.Cbor.encode {
  | Ok(bytes) => bytes
  | Error(_) => JsError.throwWithMessage(`${JSON.stringify(json)}: not written`)
  }

/** A bundle as a case gives it, its issuer section as JSON or as hex, or neither. */
let bundle = (json): Contracts.Bundle.t => {
  let body = dict{}
  switch (member(json, "issuer"), member(json, "issuerHex")) {
  | (Some(issuer), None) => body->Dict.set("issuer", section(issuer))
  | (None, Some(raw)) => body->Dict.set("issuer", hex(raw))
  | (None, None) => ()
  | (Some(_), Some(_)) => JsError.throwWithMessage(`${JSON.stringify(json)}: two issuer sections`)
  }
  {
    version: 1.,
    scope: json->at(["scope"])->number,
    generation: json->at(["generation"])->number,
    certificates: [],
    body,
  }
}

/** Values as a record holds them, `allowance-value` by its name. */
let needs = json => json->object->Dict.mapValues(v => v->decoded(Contracts.AllowanceValue.fromJson))

/** A value as the vocabulary compares it, written as `allowance-value` writes it. */
let value = (json): Needs.value =>
  switch json->at(["name"])->string {
  | "flag" =>
    switch json->at(["value"])->JSON.Decode.bool {
    | Some(b) => Flag(b)
    | None => JsError.throwWithMessage(`${JSON.stringify(json)}: no yes or no`)
    }
  | "amount" => Amount(json->at(["value"])->number)
  | "one" => One(json->at(["value"])->string)
  | "some" => Subset(json->at(["values"])->items->Array.map(string))
  | name => JsError.throwWithMessage(`${name}: no value's name`)
  }

let values = json => json->object->Dict.mapValues(value)

let status = (json): Contracts.ScopeStatus.t => json->decoded(Contracts.ScopeStatus.fromJson)

let side = json =>
  switch json->string {
  | "need" => Needs.Need
  | "held" => Held
  | name => JsError.throwWithMessage(`${name}: no side`)
  }

/** A failure as a case names it, `{unknown}`, `{mistyped, side}` or `{exceeds, need, held}`. */
let failure = (json): Needs.failure =>
  switch (member(json, "unknown"), member(json, "mistyped"), member(json, "exceeds")) {
  | (Some(name), None, None) => Unknown(string(name))
  | (None, Some(name), None) => Mistyped({name: string(name), side: json->at(["side"])->side})
  | (None, None, Some(name)) =>
    Exceeds({
      name: string(name),
      need: json->at(["need"])->value,
      held: json->at(["held"])->value,
    })
  | _ => JsError.throwWithMessage(`${JSON.stringify(json)}: no one failure`)
  }

/** What a need's case expects, `Ok` where it fits. */
let refused = (json): result<unit, Held.refused> =>
  switch (json->JSON.Decode.string, member(json, "unfit")) {
  | (Some("suspended"), None) => Error(Suspended)
  | (Some("deleted"), None) => Error(Deleted)
  | (None, Some(failed)) => Error(Unfit(failed->items->Array.map(failure)))
  | (None, None) if json == JSON.Null => Ok()
  | _ => JsError.throwWithMessage(`${JSON.stringify(json)}: no one refusal`)
  }

/** A step of where a value was malformed, `{field}` or `{key}`. */
let step = (json): Envelope.Malformed.step =>
  switch (member(json, "field"), member(json, "key")) {
  | (Some(name), None) => Field(string(name))
  | (None, Some(key)) => Key(string(key))
  | _ => JsError.throwWithMessage(`${JSON.stringify(json)}: no one step`)
  }

/** Why a case's bundle holds no scope, `{other}`, `{absent}` or `{malformed, expected}`. */
let unheld = (json): Held.unheld =>
  switch (member(json, "other"), member(json, "absent"), member(json, "malformed")) {
  | (Some(id), None, None) => Other(number(id))
  | (None, Some(_), None) => Absent
  | (None, None, Some(steps)) =>
    Malformed({at: steps->items->Array.map(step), expected: json->at(["expected"])->string})
  | _ => JsError.throwWithMessage(`${JSON.stringify(json)}: no one reason`)
  }
