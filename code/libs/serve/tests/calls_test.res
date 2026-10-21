/***
 * `Calls.serve` held to `src/calls.resi`: a call read in either form and answered in either, CBOR
 * where `Accept` names neither; each status by failure and reason; a reason's own message unless
 * one is given; a reason no operation declares answered `unknown`, a throwing handler and an output
 * that cannot be written `fault`; a request read as no call `malformed`; and a signed call verified to
 * its signer, or `denied`, by the records of `tests/capability/signed.json`.
 */
open Node
open Served

let messageOf = reason => Contracts.messages->Dict.get(reason)->Option.getOr("")

test("a call in JSON, answered in JSON where Accept asks", async () => {
  let response = await serve(
    request(
      ~contentType="application/json",
      ~accept="application/json",
      "/object/describe",
      json(describe("a")),
    ),
  )
  deepEqual((response.status, response.contentType), (200, "application/json"))
  deepEqual(
    response.body->text->JSON.parseOrThrow,
    JSON.parseOrThrow(`{"status": "success", "data": {"name": "a unsigned"}}`),
  )
})

test("a call in CBOR, answered in CBOR, written byte for byte", async () => {
  let response = await serve(
    request(
      ~contentType="application/cbor",
      ~accept="application/cbor",
      "/object/describe",
      inCbor(describe("a")),
    ),
  )
  deepEqual((response.status, response.contentType), (200, "application/cbor"))
  // {0: 1, 1: {1: "a unsigned"}}
  deepEqual(hex(response.body), "a2000101a1016a6120756e7369676e6564")
})

test("CBOR where the request names neither form", async () => {
  let unnamed = await serve(request("/object/describe", inCbor(describe("a"))))
  deepEqual((unnamed.status, unnamed.contentType), (200, "application/cbor"))
  deepEqual(answerOf(unnamed), success("a unsigned"))
  let other = await serve(
    request(
      ~contentType="application/json",
      ~accept="text/html",
      "/object/describe",
      json(describe("a")),
    ),
  )
  deepEqual((other.status, other.contentType), (200, "application/cbor"))
  deepEqual(answerOf(other), success("a unsigned"))
})

test("the first form Accept names, its parameters and its case passed over", async () => {
  let response = await serve(
    request(
      ~contentType="Application/JSON; charset=utf-8",
      ~accept="text/html, application/json;q=0.9, application/cbor",
      "/object/describe",
      json(describe("a")),
    ),
  )
  deepEqual((response.status, response.contentType), (200, "application/json"))
  deepEqual(answerOf(response), success("a unsigned"))
})

test("each failure its status, and denied, not_found and rate_limited their own", async () => {
  let cases = [
    (
      "/object/read",
      {Objects.call: Read({name: "a"}), capabilities: []},
      404,
      Contracts.Failure.Rejected,
      "not_found",
    ),
    ("/object/describe", describe("denied"), 403, Rejected, "denied"),
    (
      "/object/write",
      {call: Write({name: "a", content: utf8("a")}), capabilities: []},
      400,
      Rejected,
      "too_large",
    ),
    (
      "/object/write",
      {call: Write({name: "full", content: utf8("a")}), capabilities: []},
      503,
      Unavailable,
      "storage_full",
    ),
    (
      "/object/delete",
      {call: Delete({name: "a"}), capabilities: []},
      503,
      Unavailable,
      "overloaded",
    ),
    ("/object/describe", describe("paced"), 429, Unavailable, "rate_limited"),
    ("/object/describe", describe("throw"), 500, Unknown, "fault"),
  ]
  for i in 0 to cases->Array.length - 1 {
    switch cases->Array.get(i) {
    | Some((path, call, status, failure, reason)) =>
      let response = await serve(request(~accept="application/json", path, inCbor(call)))
      deepEqual(
        (
          response.status,
          answerOf(response)->Result.map(a =>
            switch a {
            | Success(_) => None
            | Error(e) => Some((e.failure, e.reason))
            }
          ),
        ),
        (status, Ok(Some((failure, reason)))),
        ~message=reason,
      )
    | None => ()
    }
  }
})

test("a reason's own message, unless one is given", async () => {
  let gone = await serve(
    request("/object/read", inCbor({call: Read({name: "a"}), capabilities: []})),
  )
  deepEqual(answerOf(gone), error(Rejected, "not_found", messageOf("not_found")))
  let big = await serve(
    request(
      "/object/write",
      inCbor({call: Write({name: "a", content: utf8("a")}), capabilities: []}),
    ),
  )
  deepEqual(answerOf(big), error(Rejected, "too_large", "over its bound of 1 MiB"))
  let busy = await serve(
    request("/object/delete", inCbor({call: Delete({name: "a"}), capabilities: []})),
  )
  deepEqual(answerOf(busy), error(Unavailable, "overloaded", messageOf("overloaded")))
  let paced = await serve(request("/object/describe", inCbor(describe("paced"))))
  deepEqual(answerOf(paced), error(Unavailable, "rate_limited", messageOf("rate_limited")))
})

test("a reason its operation does not declare is unknown, its reason as given", async () => {
  let stale = await serve(request("/object/describe", inCbor(describe("stale"))))
  deepEqual(stale.status, 500)
  deepEqual(answerOf(stale), error(Unknown, "stale", messageOf("stale")))
  let said = await serve(request("/object/describe", inCbor(describe("stale, said"))))
  deepEqual(answerOf(said), error(Unknown, "stale", "changed"))
  // `stopped` is a call between apps', which no operation of the platform's declares.
  let stopped = await serve(
    request("/object/list", inCbor({call: List({prefix: ""}), capabilities: []})),
  )
  deepEqual(answerOf(stopped), error(Unknown, "stopped", messageOf("stopped")))
})

test("a handler that throws or rejects is a fault", async () => {
  let thrown = await serve(request("/object/describe", inCbor(describe("throw"))))
  let rejected = await serve(request("/object/describe", inCbor(describe("reject"))))
  [thrown, rejected]->Array.forEach(response => {
    deepEqual(response.status, 500)
    deepEqual(
      answerOf(response)->Result.map(
        a =>
          switch a {
          | Success(_) => None
          | Error(e) => Some((e.failure, e.reason))
          },
      ),
      Ok(Some((Contracts.Failure.Unknown, "fault"))),
    )
  })
})

test("an output its writers cannot write is a fault, in either form", async () => {
  let inJson = await serve(
    request(~accept="application/json", "/object/describe", inCbor(describe("unwritable"))),
  )
  let inCbor = await serve(request("/object/describe", inCbor(describe("unwritable"))))
  deepEqual(
    (inJson.status, inJson.contentType, inCbor.status, inCbor.contentType),
    (500, "application/json", 500, "application/cbor"),
  )
  deepEqual(
    [inJson, inCbor]->Array.map(r =>
      answerOf(r)->Result.map(
        a =>
          switch a {
          | Success(_) => None
          | Error(e) => Some(e.reason)
          },
      )
    ),
    [Ok(Some("fault")), Ok(Some("fault"))],
  )
})

test("a request read as no call is malformed", async () => {
  let call = json(describe("a"))
  let cases = [
    ("a path of no operation", request(~contentType="application/json", "/object", call)),
    ("a path too deep", request(~contentType="application/json", "/object/describe/a", call)),
    ("an interface not served", request(~contentType="application/json", "/blob/get", call)),
    (
      "an operation the interface has not",
      request(~contentType="application/json", "/object/rename", call),
    ),
    (
      "a path naming another operation",
      request(~contentType="application/json", "/object/read", call),
    ),
    (
      "a path naming another interface",
      request(~contentType="application/json", "/issuer/for_space", call),
    ),
    (
      "a method but POST",
      request(~method_="GET", ~contentType="application/json", "/object/describe", call),
    ),
    ("a form neither", request(~contentType="text/plain", "/object/describe", call)),
    (
      "JSON that is not JSON",
      request(~contentType="application/json", "/object/describe", utf8("{")),
    ),
    (
      "JSON that is no UTF-8",
      request(~contentType="application/json", "/object/describe", Uint8Array.fromArray([0xff])),
    ),
    (
      "JSON that is no call",
      request(~contentType="application/json", "/object/describe", utf8("[1]")),
    ),
    ("CBOR that is not CBOR", request("/object/describe", Uint8Array.fromArray([0xff]))),
    ("CBOR left over", request("/object/describe", Uint8Array.fromArray([0x01, 0x01]))),
    ("CBOR that is no call", request("/object/describe", cbor(Integer(1n)))),
    (
      "an input not as its type",
      request(
        ~contentType="application/json",
        "/object/describe",
        utf8(`{"interface": "object", "operation": "describe", "input": {"name": 1}}`),
      ),
    ),
  ]
  for i in 0 to cases->Array.length - 1 {
    switch cases->Array.get(i) {
    | Some((what, request)) =>
      let response = await serve(request)
      deepEqual(response.status, 400, ~message=what)
      switch errorOf(response) {
      | Some({failure, reason, message}) =>
        deepEqual((failure, reason), (Contracts.Failure.Rejected, "malformed"), ~message=what)
        ok(message->String.startsWith(messageOf("malformed")), ~message=what)
      | None => ok(false, ~message=`${what}: no error`)
      }
    | None => ()
    }
  }
})

test("a malformed input says where", async () => {
  let response = await serve(
    request(
      ~contentType="application/json",
      "/object/describe",
      utf8(`{"interface": "object", "operation": "describe", "input": {"name": 1}}`),
    ),
  )
  switch errorOf(response) {
  | Some({message}) => ok(message->String.includes("at input.name"), ~message)
  | None => ok(false, ~message="no error")
  }
})

/** The sample's records and its trust, a case's by what it says. */
let signed = "tests/capability/signed.json"

let sample = readFileSync(fromRoot(signed))->JSON.parseOrThrow

let member = (json, name) =>
  switch json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(name)) {
  | Some(value) => value
  | None => JsError.throwWithMessage(`no ${name}`)
  }

let string = json => json->JSON.Decode.string->Option.getOrThrow

let fromHex = text =>
  Uint8Array.fromArray(
    Array.fromInitializer(~length=String.length(text) / 2, i =>
      text->String.slice(~start=2 * i, ~end=2 * i + 2)->Int.fromString(~radix=16)->Option.getOrThrow
    ),
  )

let caseOf = what =>
  sample
  ->member("cases")
  ->JSON.Decode.array
  ->Option.getOrThrow
  ->Array.find(c => c->member("what")->string == what)
  ->Option.getOrThrow

let trustOf = (item, ~reads): Calls.trust =>
  () => {
    reads := reads.contents + 1
    {
      root: sample->member("root")->string->fromHex,
      certificates: item
      ->member("certificates")
      ->JSON.Decode.array
      ->Option.getOrThrow
      ->Array.map(name => sample->member("certificates")->member(name->string)->string->fromHex),
      now: item->member("now")->JSON.Decode.float->Option.getOrThrow,
    }
  }

let component = caseOf("a call a component signs, its certificate carried in kcwt")

test("a signed call verified, its signer handed on as the caller", async () => {
  let reads = ref(0)
  let trust = trustOf(component, ~reads)
  let body = component->member("record")->string->fromHex
  let response = await Calls.serve(routes, ~trust, request("/issuer/for_space", body))
  deepEqual(response.status, 200)
  deepEqual(answerOf(response), success("component storage"))
  // The trust is read again at each request, so a newer bundle takes effect.
  let again = await Calls.serve(routes, ~trust, request("/issuer/for_space", body))
  deepEqual((again.status, reads.contents), (200, 2))
  // A signed call's path is held to its payload's names as an unsigned one's is.
  let elsewhere = await Calls.serve(routes, ~trust, request("/issuer/for_app", body))
  deepEqual(elsewhere.status, 400)
})

test("a signed call whose signature fails is denied", async () => {
  let reads = ref(0)
  let trust = trustOf(component, ~reads)
  let body = component->member("record")->string->fromHex
  let last = body->TypedArray.length - 1
  let broken = body->TypedArray.copy
  broken->TypedArray.set(last, body->TypedArray.get(last)->Option.getOrThrow->Int.bitwiseXor(1))
  let response = await Calls.serve(routes, ~trust, request("/issuer/for_space", broken))
  deepEqual(response.status, 403)
  deepEqual(answerOf(response), error(Rejected, "denied", messageOf("denied")))
  let unknown = caseOf("a call signed by a key no certificate given certifies")
  let response = await Calls.serve(
    routes,
    ~trust=trustOf(unknown, ~reads),
    request("/issuer/for_space", unknown->member("record")->string->fromHex),
  )
  deepEqual(answerOf(response), error(Rejected, "denied", messageOf("denied")))
})

test("an unsigned call reads no trust", async () => {
  reads := 0
  let _ = await serve(request("/object/describe", inCbor(describe("a"))))
  deepEqual(reads.contents, 0)
})
