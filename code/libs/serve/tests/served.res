/***
 * What the tests serve: `object`, whose handler answers by the name it is given, and `issuer`,
 * which answers who called; requests written in either form, and answers read back from either.
 */
open Node

module Contracts = Envelope.Contracts
module Objects = Contracts.Interface.Object
module Issuer = Contracts.Interface.Issuer
module Named = Contracts.ObjectName
module Answer = Contracts.Answer

let named = (name): Calls.answer => Output(
  Calls.output({Named.name: name}, ~toJson=Named.toJson, ~toCbor=Named.toCbor),
)

let refused = (reason, ~message=?): Calls.answer => Refused({reason, message})

/** Who called, as a name: `unsigned`, `root`, or a certificate's role and its `sub`. */
let callerName = (caller: Calls.caller) =>
  switch caller {
  | Unsigned => "unsigned"
  | Signed(Root) => "root"
  | Signed(Signed({role, sub})) => [role, sub->Option.getOr("")]->Array.join(" ")->String.trim
  }

/** `describe` answers by its name, a handler's every way of answering; the rest answer one reason. */
let answerObject = (caller, envelope: Objects.envelope) =>
  switch envelope.call {
  | Describe({name: "throw"}) => JsError.throwWithMessage("thrown")
  | Describe({name: "reject"}) => Promise.reject(JsExn.anyToExnInternal("rejected"))
  | Describe({name: "denied"}) => Promise.resolve(refused("denied"))
  | Describe({name: "paced"}) => Promise.resolve(refused("rate_limited"))
  | Describe({name: "stale"}) => Promise.resolve(refused("stale"))
  | Describe({name: "stale, said"}) => Promise.resolve(refused("stale", ~message="changed"))
  | Describe({name: "unwritable"}) =>
    Promise.resolve(
      Calls.Output(
        Calls.output(
          (),
          ~toJson=() => JsError.throwWithMessage("no JSON"),
          ~toCbor=() => Codec.Cbor.Integer(18446744073709551616n),
        ),
      ),
    )
  | Describe({name}) => Promise.resolve(named(`${name} ${callerName(caller)}`))
  | Read(_) => Promise.resolve(refused("not_found"))
  | Write({name: "full"}) => Promise.resolve(refused("storage_full"))
  | Write(_) => Promise.resolve(refused("too_large", ~message="over its bound of 1 MiB"))
  | Delete(_) => Promise.resolve(refused("overloaded"))
  | List(_) => Promise.resolve(refused("stopped"))
  }

let object = Calls.route({
  name: "object",
  fromJson: Objects.fromJson,
  fromCbor: Objects.fromCbor,
  reasons: [Objects.write, Objects.read, Objects.describe, Objects.delete, Objects.list],
  handle: answerObject,
})

let issuer = Calls.route({
  name: "issuer",
  fromJson: Issuer.fromJson,
  fromCbor: Issuer.fromCbor,
  reasons: [Issuer.forApp, Issuer.forSpace],
  handle: async (caller, envelope) =>
    switch envelope.call {
    | ForSpace({space: Storage}) => named(callerName(caller))
    | ForSpace({space: Compute | Database}) | ForApp(_) => refused("not_permitted")
    },
})

let routes = [object, issuer]

/** A trust no unsigned call reads, counting each time it is read. */
let reads = ref(0)
let untrusted = (): Capability.Signed.trust => {
  reads := reads.contents + 1
  {root: Uint8Array.fromLength(32), certificates: [], now: 0.}
}

let cbor = value =>
  switch Codec.Cbor.encode(value) {
  | Ok(bytes) => bytes
  | Error(_) => JsError.throwWithMessage("unwritable")
  }

let decoded = bytes =>
  switch Codec.Cbor.decode(bytes) {
  | Ok(value) => value
  | Error(_) => JsError.throwWithMessage("no CBOR")
  }

let json = (call: Objects.envelope) => call->Objects.toJson->JSON.stringify->utf8
let inCbor = (call: Objects.envelope) => call->Objects.toCbor->cbor

let describe = name => {Objects.call: Describe({name: name}), capabilities: []}

/** A request of `path`, POST unless told. */
let request = (~method_="POST", ~contentType=?, ~accept=?, path, body): Calls.request => {
  method_,
  path,
  contentType,
  accept,
  body,
}

let serve = request => Calls.serve(routes, ~trust=untrusted, request)

/** A response's answer read back in the form its `Content-Type` names. */
let answerOf = (response: Calls.response) =>
  switch response.contentType {
  | "application/json" => Answer.fromJson(response.body->text->JSON.parseOrThrow, Named.fromJson)
  | "application/cbor" => Answer.fromCbor(response.body->decoded, Named.fromCbor)
  | other => JsError.throwWithMessage(`${other}: neither form`)
  }

/** The error a response answers, if it answers one. */
let errorOf = response =>
  switch answerOf(response) {
  | Ok(Error(error)) => Some(error)
  | Ok(Success(_)) | Error(_) => None
  }

let success = (name): result<Answer.t<Named.t>, Envelope.Malformed.t> => Ok(Success({name: name}))

let error = (failure, reason, message): result<Answer.t<Named.t>, Envelope.Malformed.t> => Ok(
  Error({failure, reason, message}),
)

/** The bytes as hex, for a message. */
let hex = bytes =>
  bytes
  ->TypedArray.toString
  ->String.split(",")
  ->Array.map(b =>
    b->Int.fromString->Option.getOr(0)->Int.toString(~radix=16)->String.padStart(2, "0")
  )
  ->Array.join("")
