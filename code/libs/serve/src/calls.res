module Contracts = Envelope.Contracts
module Answer = Contracts.Answer
module Cbor = Codec.Cbor

type request = {
  method_: string,
  path: string,
  contentType: option<string>,
  accept: option<string>,
  body: Uint8Array.t,
}

type response = {status: int, contentType: string, body: Uint8Array.t}

type caller = Signed(Capability.Signed.signer) | Unsigned

type output = {json: unit => JSON.t, cbor: unit => Cbor.value}

let output = (value, ~toJson, ~toCbor) => {json: () => toJson(value), cbor: () => toCbor(value)}

type answer = Output(output) | Refused({reason: string, message: option<string>})

type interface_<'envelope> = {
  name: string,
  fromJson: JSON.t => result<'envelope, Envelope.Malformed.t>,
  fromCbor: Cbor.value => result<'envelope, Envelope.Malformed.t>,
  reasons: array<Envelope.Contracts.operation>,
  handle: (caller, 'envelope) => promise<answer>,
}

/** A form a call is read in or an answer written in. */
type form = Json | Cbor

/** A call's body as its form reads it, before its interface reads it. */
type body = InJson(JSON.t) | InCbor(Cbor.value)

type route = {
  name: string,
  operations: array<Contracts.operation>,
  /** The call read as the interface's envelope, and its handler ready to answer it. */
  read: (caller, body) => result<unit => promise<answer>, Envelope.Malformed.t>,
}

let route = (i: interface_<'envelope>) => {
  name: i.name,
  operations: i.reasons,
  read: (caller, body) =>
    switch body {
    | InJson(json) => i.fromJson(json)
    | InCbor(cbor) => i.fromCbor(cbor)
    }->Result.map(envelope => () => i.handle(caller, envelope)),
}

type trust = unit => Capability.Signed.trust

let mediaType = form =>
  switch form {
  | Json => "application/json"
  | Cbor => "application/cbor"
  }

/** A media type's form, its parameters and its case passed over, or none where it is neither. */
let formOf = text =>
  switch text->String.split(";")->Array.get(0)->Option.getOr("")->String.trim->String.toLowerCase {
  | "application/json" => Some(Json)
  | "application/cbor" => Some(Cbor)
  | _ => None
  }

/** The form an answer is written in: the first `Accept` names of the two, CBOR where it names neither. */
let answerForm = accept =>
  accept
  ->Option.flatMap(accept => accept->String.split(",")->Array.findMap(formOf))
  ->Option.getOr(Cbor)

/** An error's HTTP status, by its failure, and by its reason for `denied`, `not_found` and `rate_limited`. */
let statusOf = (error: Contracts.Error.t) =>
  switch error.failure {
  | Rejected =>
    switch error.reason {
    | "denied" => 403
    | "not_found" => 404
    | _ => 400
    }
  | Unavailable =>
    switch error.reason {
    | "rate_limited" => 429
    | _ => 503
    }
  | Unknown => 500
  }

/** The answer's bytes in the form, or none where an output's writers throw or write no CBOR. */
let encoded = (form, answer: Answer.t<output>) =>
  try switch form {
  | Json => Some(Answer.toJson(answer, o => o.json())->JSON.stringify->Web.utf8)
  | Cbor =>
    switch Answer.toCbor(answer, o => o.cbor())->Cbor.encode {
    | Ok(bytes) => Some(bytes)
    | Error(_) => None
    }
  } catch {
  | _ => None
  }

/** An output that could not be written, the implementation's fault, RFC ge55b. */
let unwritten: Contracts.Error.t = {
  failure: Unknown,
  reason: "fault",
  message: "The implementation answered an output that could not be written",
}

let written = (form, answer: Answer.t<output>) => {
  let status = switch answer {
  | Success(_) => 200
  | Error(error) => statusOf(error)
  }
  switch encoded(form, answer) {
  | Some(body) => {status, contentType: mediaType(form), body}
  | None => {
      status: statusOf(unwritten),
      contentType: mediaType(form),
      body: encoded(form, Error(unwritten))->Option.getOr(Uint8Array.fromLength(0)),
    }
  }
}

/** The reason's message as `Contracts.messages` gives it, or the text given. */
let messageOf = (reason, fallback) => Contracts.messages->Dict.get(reason)->Option.getOr(fallback)

/** An error by a reason the operation or every operation declares, its message the reason's own. */
let refusal = (declared: array<Contracts.reason>, reason, message): Contracts.Error.t =>
  switch declared->Array.concat(Contracts.reasons)->Array.find(r => r.name == reason) {
  | Some(r) => {failure: r.failure, reason, message: message->Option.getOr(r.message)}
  // A reason its operation does not declare is the handler's bug, answered `unknown`, RFC ge55b.
  | None => {
      failure: Unknown,
      reason,
      message: switch message {
      | Some(message) => message
      | None =>
        messageOf(reason, "The implementation answered a reason its operation does not declare")
      },
    }
  }

let malformed = message =>
  refusal([], "malformed", Some(`${messageOf("malformed", "")}: ${message}`))

let denied = refusal([], "denied", None)

/** What a handler threw, the implementation's fault, RFC ge55b. */
let thrown = refusal([], "fault", None)

/** Where a value was not read as its type, and what was expected there. */
let explained = (m: Envelope.Malformed.t) => {
  let at =
    m.at
    ->Array.map(step =>
      switch step {
      | Field(name) => name
      | Index(index) => Int.toString(index)
      | Key(key) => key
      }
    )
    ->Array.join(".")
  at == "" ? `${m.expected} expected` : `at ${at}, ${m.expected} expected`
}

let text = (value: Cbor.value) =>
  switch value {
  | Text(text) => Some(text)
  | Integer(_)
  | Bytes(_)
  | Array(_)
  | Map(_)
  | Tag(_)
  | Bool(_)
  | Null
  | Undefined
  | Simple(_)
  | Float(_) =>
    None
  }

let integer = (value: Cbor.value) =>
  switch value {
  | Integer(n) => Some(n)
  | Text(_)
  | Bytes(_)
  | Array(_)
  | Map(_)
  | Tag(_)
  | Bool(_)
  | Null
  | Undefined
  | Simple(_)
  | Float(_) =>
    None
  }

/** Whether a value is a Sign1 under tag 18, a call a certificate made. */
let signed = (value: Cbor.value) =>
  switch value {
  | Tag(tag, _) => tag == 18n
  | Integer(_)
  | Text(_)
  | Bytes(_)
  | Array(_)
  | Map(_)
  | Bool(_)
  | Null
  | Undefined
  | Simple(_)
  | Float(_) => false
  }

/** The interface and the operation a call names of itself, as its JSON or its CBOR holds them. */
let namesOf = body =>
  switch body {
  | InJson(json) => {
      let named = name =>
        json
        ->JSON.Decode.object
        ->Option.flatMap(o => o->Dict.get(name))
        ->Option.flatMap(JSON.Decode.string)
      (named("interface"), named("operation"))
    }
  | InCbor(value) => {
      let pairs = switch value {
      | Map(pairs) => pairs
      | Integer(_)
      | Text(_)
      | Bytes(_)
      | Array(_)
      | Tag(_)
      | Bool(_)
      | Null
      | Undefined
      | Simple(_)
      | Float(_) => []
      }
      let named = key =>
        pairs
        ->Array.find(((k, _)) => integer(k)->Option.mapOr(false, n => n == key))
        ->Option.flatMap(((_, v)) => text(v))
      (named(1n), named(2n))
    }
  }

/** The call's body in the form `Content-Type` names, and who signed it, or why it is refused. */
let bodyOf = (request: request, ~trust: trust) =>
  switch request.contentType->Option.mapOr(Some(Cbor), formOf) {
  | None => Error(malformed("the Content-Type is neither application/json nor application/cbor"))
  | Some(Json) =>
    switch Web.fromUtf8(request.body) {
    | None => Error(malformed("the body is not UTF-8"))
    | Some(text) =>
      try Ok((InJson(JSON.parseOrThrow(text)), Unsigned)) catch {
      | JsExn(_) => Error(malformed("the body is not JSON"))
      }
    }
  | Some(Cbor) =>
    switch Cbor.decode(request.body) {
    | Error(_) => Error(malformed("the body is not one CBOR data item"))
    | Ok(value) if signed(value) =>
      switch Capability.Signed.verify(trust(), Call, request.body) {
      | Ok({content, signer}) => Ok((InCbor(content), Signed(signer)))
      | Error(_) => Error(denied)
      }
    | Ok(value) => Ok((InCbor(value), Unsigned))
    }
  }

/** The answer to a request, as `Answer` holds it, the handler's or the refusal reading it gives. */
let answered = async (routes: array<route>, ~trust, request: request): Answer.t<output> => {
  let parts = request.path->String.split("/")
  let named = switch parts {
  | ["", interface, operation] if interface != "" && operation != "" => Some((interface, operation))
  | _ => None
  }
  let found = switch named {
  | None => Error(malformed(`the path ${request.path} is not /{interface}/{operation}`))
  | Some((interface, operation)) =>
    switch routes->Array.find(r => r.name == interface) {
    | None => Error(malformed(`no interface ${interface} is served here`))
    | Some(route) =>
      switch route.operations->Array.find(o => o.name == operation) {
      | None => Error(malformed(`the interface ${interface} has no operation ${operation}`))
      | Some(declared) => Ok((route, declared))
      }
    }
  }
  let ready = switch (request.method_, found) {
  | (_, Error(error)) => Error(error)
  | ("POST", Ok((route, declared))) =>
    switch bodyOf(request, ~trust) {
    | Error(error) => Error(error)
    | Ok((body, caller)) =>
      switch namesOf(body) {
      | (Some(interface), _) if interface != route.name =>
        Error(malformed(`the call names the interface ${interface}, the path ${route.name}`))
      | (_, Some(operation)) if operation != declared.name =>
        Error(malformed(`the call names the operation ${operation}, the path ${declared.name}`))
      | _ =>
        route.read(caller, body)
        ->Result.map(run => (run, declared))
        ->Result.mapError(m => malformed(explained(m)))
      }
    }
  | (method_, Ok(_)) => Error(malformed(`a call is POST, never ${method_}`))
  }
  switch ready {
  | Error(error) => Error(error)
  | Ok((run, declared)) =>
    switch await run() {
    | Output(output) => Success(output)
    | Refused({reason, message}) => Error(refusal(declared.reasons, reason, message))
    | exception _ => Error(thrown)
    }
  }
}

let serve = async (routes, ~trust, request) =>
  written(answerForm(request.accept), await answered(routes, ~trust, request))
