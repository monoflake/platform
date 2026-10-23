/***
 * A tiny implementation of `object` over HTTP for the end-to-end test, keeping every call's body,
 * RFC ge55b. `list` answers with no answer at all.
 */
open Node
module Cbor = Codec.Cbor
module Contracts = Envelope.Contracts
module Object = Contracts.Interface.Object

let written = value =>
  switch Cbor.encode(value) {
  | Ok(bytes) => bytes
  | Error(_) => JsError.throwWithMessage("unwritable")
  }

let bytesOf = (value: Cbor.value) =>
  switch value {
  | Bytes(bytes) => Some(bytes)
  | Integer(_)
  | Text(_)
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

let read = (bytes, certificate) =>
  switch Cbor.decode(bytes) {
  | Ok(value) =>
    Object.fromCbor(value)->Result.map(call => (call, certificate))->Result.mapError(_ => ())
  | Error(_) => Error()
  }

/** A call as its envelope, and the certificate that signed it, where one did. */
let callOf = (contentType, body) =>
  if contentType->String.startsWith("application/cbor") {
    switch Codec.Sign1.decode(body) {
    | Ok(({payload: Some(payload), unprotected}, true)) =>
      read(
        payload,
        unprotected->Array.findMap(((key, value)) =>
          key == Cbor.Integer(13n) ? bytesOf(value) : None
        ),
      )
    | Ok(_) | Error(_) => read(body, None)
    }
  } else {
    switch JSON.parseOrThrow(Web.text(body)) {
    | json => Object.fromJson(json)->Result.map(call => (call, None))->Result.mapError(_ => ())
    | exception JsExn(_) => Error()
    }
  }

/** What a handler answers, an output by its writers, or an error and its HTTP status. */
type answer =
  | Output(JSON.t, Cbor.value)
  | Refused(int, Contracts.Error.t)

let output = (value, toJson, toCbor) => Output(toJson(value), toCbor(value))

let respond = (response, ~cbor, answer) => {
  let (status, json, value) = switch answer {
  | Output(json, value) => (
      200,
      Contracts.Answer.toJson(Success(json), json => json),
      Contracts.Answer.toCbor(Success(value), value => value),
    )
  | Refused(status, error) => (
      status,
      Contracts.Answer.toJson(Error(error), json => json),
      Contracts.Answer.toCbor(Error(error), value => value),
    )
  }
  response->writeHead(status, dict{"content-type": cbor ? "application/cbor" : "application/json"})
  response->end(cbor ? written(value) : Web.utf8(JSON.stringify(json)))
}

let handle = (objectsOf: dict<string> => option<dict<Uint8Array.t>>, bodies, authorizations) =>
  (request, response) =>
    body(request)
    ->Promise.thenResolve(bytes => {
      bodies->Array.push(bytes)
      let headers = request->requestHeaders
      authorizations->Array.push(headers->Dict.get("authorization"))
      let accept = headers->Dict.get("accept")->Option.getOr("application/cbor")
      let cbor = !(accept->String.startsWith("application/json"))
      let contentType = headers->Dict.get("content-type")->Option.getOr("")
      if request->path == "/object/list" {
        response->writeHead(502, dict{"content-type": "text/plain"})
        response->end(Web.utf8("bad gateway"))
      } else {
        let answer = switch (objectsOf(headers), callOf(contentType, bytes)) {
        | (None, _) =>
          Refused(403, {failure: Rejected, reason: "denied", message: "no binding's token"})
        | (_, Error()) =>
          Refused(400, {failure: Rejected, reason: "malformed", message: "not a call of object"})
        | (Some(objects), Ok(({call}, certificate))) =>
          switch call {
          | Write({name, content}) =>
            objects->Dict.set(name, certificate->Option.getOr(content))
            output(
              ({}: Contracts.ObjectWritten.t),
              Contracts.ObjectWritten.toJson,
              Contracts.ObjectWritten.toCbor,
            )
          | Read({name}) =>
            switch objects->Dict.get(name) {
            | Some(content) =>
              output(
                (
                  {
                    content,
                    size: Int.toFloat(TypedArray.length(content)),
                  }: Contracts.ObjectContent.t
                ),
                Contracts.ObjectContent.toJson,
                Contracts.ObjectContent.toCbor,
              )
            | None =>
              Refused(404, {failure: Rejected, reason: "not_found", message: "no such object"})
            }
          | Describe({name}) =>
            let described: Contracts.ObjectDescribed.t = switch objects->Dict.get(name) {
            | Some(content) => {size: Int.toFloat(TypedArray.length(content))}
            | None => {}
            }
            output(described, Contracts.ObjectDescribed.toJson, Contracts.ObjectDescribed.toCbor)
          | Delete({name}) =>
            objects->Dict.delete(name)
            output(
              ({}: Contracts.ObjectDeleted.t),
              Contracts.ObjectDeleted.toJson,
              Contracts.ObjectDeleted.toCbor,
            )
          | List(_) => Refused(500, {failure: Unknown, reason: "unknown", message: "unreachable"})
          }
        }
        respond(response, ~cbor, answer)
      }
    })
    ->ignore

/**
 * The server started at `localhost`, on the port given or one of the system's choosing, keeping
 * each body in `bodies` and each `Authorization` in `authorizations`, and where tokens are given
 * each its own objects, a call with none denied.
 */
let start = (~port=0, ~bodies=[], ~authorizations=[], ~tokens=?) =>
  Promise.make((resolve, _) => {
    let objects = Dict.make()
    let kept =
      tokens->Option.map(tokens =>
        tokens->Array.map(t => (`Bearer ${t}`, Dict.make()))->Dict.fromArray
      )
    let objectsOf = headers =>
      switch kept {
      | None => Some(objects)
      | Some(kept) => headers->Dict.get("authorization")->Option.flatMap(a => kept->Dict.get(a))
      }
    let server = createServer(handle(objectsOf, bodies, authorizations))
    server->listen(port, "localhost", () => resolve(server))
  })
