type t = {
  make: string => promise<result<string, string>>,
  route: (~tunnel: string, ~address: string) => promise<result<unit, string>>,
  token: string => promise<result<string, string>>,
}

type config = {api: string, account: string, credential: string}

let member = (json, name) => json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(name))

/** The `result` of an answer the API marked a success, or the first error it gave. */
let resultOf = (text, ~status) =>
  switch JSON.parseOrThrow(text) {
  | exception JsExn(_) => Error(`the API answered ${Int.toString(status)} and no JSON`)
  | json =>
    switch (member(json, "success")->Option.flatMap(JSON.Decode.bool), member(json, "result")) {
    | (Some(true), Some(result)) => Ok(result)
    | _ =>
      let first =
        member(json, "errors")
        ->Option.flatMap(JSON.Decode.array)
        ->Option.flatMap(errors => errors->Array.get(0))
        ->Option.flatMap(e => member(e, "message"))
        ->Option.flatMap(JSON.Decode.string)
      Error(first->Option.getOr(`the API answered ${Int.toString(status)}`))
    }
  }

let through = (config, fetch: Web.fetch) => {
  let called = async (method, path, body) => {
    let headers = dict{"authorization": `Bearer ${config.credential}`}
    let request = switch body {
    | Some(json) =>
      headers->Dict.set("content-type", "application/json")
      Web.request(
        `${config.api}/accounts/${config.account}${path}`,
        {method, headers, body: Web.utf8(JSON.stringify(json))},
      )
    | None => Web.request(`${config.api}/accounts/${config.account}${path}`, {method, headers})
    }
    switch await fetch(request) {
    | exception JsExn(_) => Error("the API could not be reached")
    | response => resultOf(await response->Web.text, ~status=response->Web.status)
    }
  }
  {
    make: async name =>
      (
        await called(
          "POST",
          "/cfd_tunnel",
          Some(JSON.Object(dict{"name": String(name), "config_src": String("cloudflare")})),
        )
      )->Result.flatMap(result =>
        member(result, "id")
        ->Option.flatMap(JSON.Decode.string)
        ->Option.mapOr(Error("the API answered a tunnel with no id"), id => Ok(id))
      ),
    // A route refused is looked for among the tunnel's, so a bind asked again finds its own made.
    route: async (~tunnel, ~address) => {
      let network = `${address}/32`
      switch await called(
        "POST",
        "/teamnet/routes",
        Some(JSON.Object(dict{"network": String(network), "tunnel_id": String(tunnel)})),
      ) {
      | Ok(_) => Ok()
      | Error(why) =>
        switch await called("GET", `/teamnet/routes?tunnel_id=${tunnel}&is_deleted=false`, None) {
        | Ok(routes)
          if routes
          ->JSON.Decode.array
          ->Option.getOr([])
          ->Array.some(r =>
            member(r, "network")->Option.flatMap(JSON.Decode.string) == Some(network)
          ) =>
          Ok()
        | Ok(_) | Error(_) => Error(why)
        }
      }
    },
    token: async tunnel =>
      (await called("GET", `/cfd_tunnel/${tunnel}/token`, None))->Result.flatMap(result =>
        result->JSON.Decode.string->Option.mapOr(Error("the API answered no token"), t => Ok(t))
      ),
  }
}
