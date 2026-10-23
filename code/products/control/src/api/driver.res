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
  | exception JsExn(_) => unreachable(`the host's driver at ${host.address} did not answer`)
  | response =>
    let text = await response->Web.text
    switch JSON.parseOrThrow(text) {
    | exception JsExn(_) =>
      unreachable(`the host's driver answered ${Int.toString(response->Web.status)} and no JSON`)
    | json =>
      switch Contracts.Answer.fromJson(json, data) {
      | Ok(Success(output)) => Ok(output)
      | Ok(Error({reason, message})) => Error({reason, message})
      | Error({expected}) =>
        unreachable(`the host's driver answered what its type does not write, ${expected}`)
      }
    }
  }
}
