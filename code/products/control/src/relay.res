type relayed = {address: string, port: int, path: string}

let pattern = /^\/relay\/(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\/([1-9][0-9]{0,4})(\/.*)?$/

let routed = path =>
  switch pattern->RegExp.exec(path) {
  | None => None
  | Some(found) =>
    switch found->RegExp.Result.matches {
    | [Some(address), Some(port), rest] =>
      Int.fromString(port)->Option.map(port => {address, port, path: rest->Option.getOr("/")})
    | _ => None
    }
  }

let objected = path => /^\/object\/[a-z_]+$/->RegExp.test(path)

/** The host's answer, or why it gave none. */
let reached = async (reach: Reach.t, made, ~binding) =>
  switch await reach.fetch(made) {
  | answer => answer
  | exception JsExn(e) =>
    let why = e->JsExn.message->Option.getOr("no message")
    Web.answered(
      ~status=502,
      `the host of binding ${Float.toString(binding)} did not answer, ${why}`,
    )
  }

let passed = async (state: State.t, reach: Reach.t, ~caller, ~ports, request, relayed, ~search) =>
  switch caller {
  | Access.Organization(organization) =>
    switch await state.addressedAt(relayed.address) {
    | Some({id, relayed: true, organization: owner})
      if owner == organization && ports->Array.includes(relayed.port) =>
      let made = Web.resent(
        `${reach.origin(~address=relayed.address, ~port=relayed.port)}${relayed.path}${search}`,
        request,
      )
      made->Web.requestHeaders->Web.deleteHeader("proxy-authorization")
      await reached(reach, made, ~binding=id)
    | Some(_) | None =>
      Web.answered(
        ~status=404,
        `nothing at ${relayed.address}:${Int.toString(
            relayed.port,
          )} is relayed for the organization`,
      )
    }
  | Operator | Host(_) | Nobody => Web.answered(~status=403, "a relay is an organization's alone")
  }

/** Whether an answer is the error a write gets for a full bucket, or for none. */
let full = async answer =>
  answer->Web.status >= 400 &&
    switch JSON.parseOrThrow(await answer->Web.cloneResponse->Web.text) {
    | exception JsExn(_) => false
    | json =>
      json
      ->JSON.Decode.object
      ->Option.flatMap(o => o->Dict.get("reason"))
      ->Option.flatMap(JSON.Decode.string) == Some("storage_full")
    }

let stored = async (state: State.t, reach: Reach.t, ~caller, ~port, ~wait, request, ~path) =>
  switch caller {
  | Access.Organization(organization) =>
    switch await state.storage(organization) {
    | Some({id, secret, address: Some(address)}) =>
      let host: Driver.host = {reach, address, port, token: Access.tokenText(id, secret)}
      let body = await request->Web.bytesOf
      let headers = request->Web.requestHeaders
      let header = name => headers->Web.header(name)->Nullable.toOption->Option.getOr("")
      let sent = () =>
        Web.request(
          `${reach.origin(~address, ~port)}${path}`,
          {
            method: "POST",
            headers: dict{
              "authorization": `Bearer ${host.token}`,
              "content-type": header("content-type"),
              "accept": header("accept"),
            },
            body,
          },
        )
      let first = await reached(reach, sent(), ~binding=id)
      if path == "/object/write" && (await full(first)) {
        switch await Deploying.bucketed(host, ~wait) {
        | Ok() => await reached(reach, sent(), ~binding=id)
        | Error({reason, message}) =>
          Web.answered(
            ~status=503,
            `no bucket was made for the organization, ${reason}, ${message}`,
          )
        }
      } else {
        first
      }
    | Some(_) | None =>
      Web.answered(~status=409, "the organization holds no binding its host bound here")
    }
  | Operator | Host(_) | Nobody => Web.answered(~status=403, "an object is an organization's alone")
  }
