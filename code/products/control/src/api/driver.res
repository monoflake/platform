module Contracts = Envelope.Contracts

type refused = {reason: string, message: string}

type host = {reach: Reach.t, address: string, port: int, token: string}

let named = (envelope, key) =>
  envelope
  ->JSON.Decode.object
  ->Option.flatMap(o => o->Dict.get(key))
  ->Option.flatMap(JSON.Decode.string)
  ->Option.getOr("")

let unreachable = message => Error({reason: "unreachable", message})
let badAnswer = message => Error({reason: "bad_answer", message})

// A step of where a value was unread, a name after a dot and an index in brackets.
let step = (s: Envelope.Malformed.step) =>
  switch s {
  | Field(name) | Key(name) => `.${name}`
  | Index(i) => `[${Int.toString(i)}]`
  }

let call = async (host, envelope, data) => {
  let path = `/${named(envelope, "interface")}/${named(envelope, "operation")}`
  let request = Web.request(
    `${host.reach.origin(~address=host.address, ~port=host.port)}${path}`,
    {
      method: "POST",
      headers: dict{
        "authorization": `Bearer ${host.token}`,
        "content-type": "application/json",
        "accept": "application/json",
      },
      body: Web.utf8(JSON.stringify(envelope)),
    },
  )
  switch await host.reach.fetch(request) {
  | exception JsExn(e) =>
    let why = e->JsExn.message->Option.getOr("no message")
    Console.error(`driver: ${host.address}, ${why}`)
    unreachable(`the host's driver at ${host.address} did not answer, ${why}`)
  | response =>
    let text = await response->Web.text
    switch JSON.parseOrThrow(text) {
    | exception JsExn(_) =>
      badAnswer(`the host's driver answered ${Int.toString(response->Web.status)} and no JSON`)
    | json =>
      switch Contracts.Answer.fromJson(json, data) {
      | Ok(Success(output)) =>
        if path == "/management/describe" {
          Compatibility.answer(
            json,
            ~driver=host.reach.origin(~address=host.address, ~port=host.port),
          )
          ->Result.map(() => output)
          ->Result.mapError(message => {reason: "invalid", message})
        } else {
          Ok(output)
        }
      | Ok(Error({reason, message})) => Error({reason, message})
      | Error({at, expected}) =>
        let where = at->Array.length == 0 ? "the answer" : at->Array.map(step)->Array.join("")
        badAnswer(
          `the host's driver answered what its type does not write at ${where}, ${expected}`,
        )
      }
    }
  }
}
