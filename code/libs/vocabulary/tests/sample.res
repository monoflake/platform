/*** The samples read as they stand from their paths, JSON through `JSON.Decode`. */

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

let object = json =>
  switch json->JSON.Decode.object {
  | Some(o) => o
  | None => JsError.throwWithMessage(`${JSON.stringify(json)}: no object`)
  }

/** A value as `allowance-value` writes it, by its `name`. */
let value = (json): Needs.value =>
  switch json->at(["name"])->string {
  | "flag" =>
    switch json->at(["value"])->JSON.Decode.bool {
    | Some(b) => Flag(b)
    | None => JsError.throwWithMessage(`${JSON.stringify(json)}: no yes or no`)
    }
  | "amount" =>
    switch json->at(["value"])->JSON.Decode.float {
    | Some(n) => Amount(n)
    | None => JsError.throwWithMessage(`${JSON.stringify(json)}: no amount`)
    }
  | "one" => One(json->at(["value"])->string)
  | "some" => Subset(json->at(["values"])->items->Array.map(string))
  | name => JsError.throwWithMessage(`${name}: no value's name`)
  }

/** Values by their names. */
let values = json => json->object->Dict.mapValues(value)

/** An entry as the product writes it. */
let entry = (json): Needs.entry => {
  let members = () => json->at(["members"])->items->Array.map(string)
  {
    name: json->at(["name"])->string,
    type_: switch json->at(["type"])->string {
    | "flag" => #flag
    | "amount" => #amount
    | "one" => #one(members())
    | "some" => #some(members())
    | "amounts" => #amounts(members())
    | name => JsError.throwWithMessage(`${name}: no type`)
    },
    default: json->at(["default"])->value,
  }
}

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

/** What a case expects, `Ok` where nothing failed. */
let expected = json =>
  switch json->at(["failed"])->items->Array.map(failure) {
  | [] => Ok()
  | failed => Error(failed)
  }
