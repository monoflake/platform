/*** `Fetch.handler` driven with node's global `Request` and `Response`, as a Worker gives them. */
open Node
open Served

let handle = Fetch.handler(routes, ~trust=untrusted)

let url = path => `https://localhost${path}`

test("a Request served, its Response the call's answer", async () => {
  let response = await handle(
    jsRequest(
      url("/object/describe"),
      {
        method: "POST",
        headers: Dict.fromArray([
          ("content-type", "application/json"),
          ("accept", "application/json"),
        ]),
        body: json(describe("a")),
      },
    ),
  )
  deepEqual(
    (response->status, response->headers->header("content-type")->Nullable.toOption),
    (200, Some("application/json")),
  )
  deepEqual(
    (await response->bodyOf)->text->JSON.parseOrThrow,
    JSON.parseOrThrow(`{"status": "success", "data": {"name": "a unsigned"}}`),
  )
})

test("a Request in CBOR, answered in CBOR, its error's status", async () => {
  let response = await handle(
    jsRequest(
      url("/object/read"),
      {
        method: "POST",
        headers: Dict.fromArray([("content-type", "application/cbor")]),
        body: inCbor({call: Read({name: "a"}), capabilities: []}),
      },
    ),
  )
  deepEqual(
    (response->status, response->headers->header("content-type")->Nullable.toOption),
    (404, Some("application/cbor")),
  )
  deepEqual(
    Answer.fromCbor((await response->bodyOf)->decoded, Named.fromCbor),
    error(Rejected, "not_found", Contracts.messages->Dict.get("not_found")->Option.getOr("")),
  )
})

test("a Request of a query and no body, its path alone read", async () => {
  let response = await handle(
    jsRequest(url("/object/describe?a=1"), {method: "GET", headers: Dict.fromArray([])}),
  )
  deepEqual(response->status, 400)
  deepEqual(
    Answer.fromCbor((await response->bodyOf)->decoded, Named.fromCbor)->Result.map(a =>
      switch a {
      | Success(_) => None
      | Error({reason}) => Some(reason)
      }
    ),
    Ok(Some("malformed")),
  )
})
