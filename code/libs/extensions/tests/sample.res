/*** The samples read as they stand, JSON through `JSON.Decode` and the contracts. */
module Contracts = Envelope.Contracts
module Base64url = Envelope.Base64url
module Hex = Envelope.Hex

/** The sample at `path`, from the repository's root. */
let read = path => Node.readFileSync(Node.fromRoot(path))->JSON.parseOrThrow

let fail = (json, what) => JsError.throwWithMessage(`${JSON.stringify(json)}: ${what}`)

/** A member of a JSON object, if it is one and has it. */
let member = (json, name) => json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(name))

/** A member that must be there, by a path of names. */
let at = (json, names) =>
  names->Array.reduce(json, (json, name) =>
    switch member(json, name) {
    | Some(value) => value
    | None => fail(json, `no ${name}`)
    }
  )

/** A member that may be absent or null. */
let optional = (json, name, decode) =>
  switch member(json, name) {
  | Some(value) if value != JSON.Null => Some(decode(value))
  | Some(_) | None => None
  }

let string = json =>
  switch json->JSON.Decode.string {
  | Some(text) => text
  | None => fail(json, "no string")
  }

let number = json =>
  switch json->JSON.Decode.float {
  | Some(n) => n
  | None => fail(json, "no number")
  }

let bool = json =>
  switch json->JSON.Decode.bool {
  | Some(b) => b
  | None => fail(json, "no yes or no")
  }

let items = json =>
  switch json->JSON.Decode.array {
  | Some(items) => items
  | None => fail(json, "no array")
  }

/** A record as the contracts read it from its JSON. */
let decoded = (json, fromJson) =>
  switch fromJson(json) {
  | Ok(value) => value
  | Error(_) => fail(json, "not as its contract writes it")
  }

/** Bytes as base64url, sealed and opaque. */
let sealed = json =>
  switch json->string->Base64url.decode {
  | Some(bytes) => bytes
  | None => fail(json, "no base64url")
  }

/** A hash as hex, of any length, so one of the wrong length can be refused. */
let hash = json =>
  switch json->string->Hex.decode {
  | Some(bytes) => bytes
  | None => fail(json, "no hex")
  }

let declared = (json): Extension.declared => {
  host: json->at(["host"])->decoded(Contracts.ExtensionHost.fromJson),
  levels: json->at(["levels"])->decoded(Contracts.Placement.fromJson),
  place: json->at(["place"])->decoded(Contracts.ExtensionPlace.fromJson),
  address: json->at(["address"])->bool,
}

let relays = json => json->decoded(Contracts.ExtensionRelays.fromJson)

let binding = (json): Extension.binding => {
  endpoint: json->at(["endpoint"])->string,
  token: json->at(["token"])->sealed,
  relays: json->at(["relays"])->relays,
  levels: ?(json->optional("levels", decoded(_, Contracts.Placement.fromJson))),
  place: ?(json->optional("place", decoded(_, Contracts.ExtensionPlace.fromJson))),
  quota: ?(json->optional("quota", number)),
  grace: ?(json->optional("grace", number)),
  management: ?(json->optional("management", sealed)),
  shell: ?(json->optional("shell", sealed)),
}

/** A failure as a case names it, `refused` naming its case and the rest its payload. */
let unbound = (json): Extension.unbound =>
  switch json->at(["refused"])->string {
  | "grace" => Grace(json->at(["grace"])->number)
  | "relays" => Relays
  | name => fail(json, `${name}: no unbound`)
  }

let unlisted = (json): Extension.unlisted =>
  switch json->at(["refused"])->string {
  | "repeated" => Repeated(json->at(["id"])->number)
  | "credentials" => Credentials(json->at(["id"])->number)
  | "hash" => Hash(json->at(["id"])->number)
  | "token" => Token(json->at(["at"])->number->Float.toInt)
  | name => fail(json, `${name}: no unlisted`)
  }

let set = (json): Extension.set =>
  switch json->string {
  | "pool" => Pool
  | "keyed" => Keyed
  | "copies" => Copies
  | name => fail(json, `${name}: no set`)
  }

let member_ = (json): Extension.member => {
  levels: json->at(["levels"])->decoded(Contracts.Placement.fromJson),
  place: json->at(["place"])->decoded(Contracts.ExtensionPlace.fromJson),
}

let listed = (json): Extension.listed => {
  id: json->at(["id"])->number,
  capacity: json->at(["capacity"])->decoded(Contracts.Capacity.fromJson),
  hashes: json->at(["hashes"])->items->Array.map(hash),
}
