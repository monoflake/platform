type listener = Driver | Entry

type relayed = {binding: float, listener: listener, path: string}

let pattern = /^\/relay\/([1-9][0-9]{0,9})\/(driver|entry)(\/.*)?$/

let routed = path =>
  switch pattern->RegExp.exec(path) {
  | None => None
  | Some(found) =>
    switch found->RegExp.Result.matches {
    | [Some(id), Some(which), rest] =>
      Float.fromString(id)->Option.map(binding => {
        binding,
        listener: which == "driver" ? Driver : Entry,
        path: rest->Option.getOr("/"),
      })
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
    switch await state.binding(relayed.binding) {
    | Some({relayed: true, organization: owner, address: Some(address)}) if owner == organization =>
      let (driver, entry) = ports
      let port = relayed.listener == Driver ? driver : entry
      let made = Web.resent(`${reach.origin(~address, ~port)}${relayed.path}${search}`, request)
      made->Web.requestHeaders->Web.deleteHeader("proxy-authorization")
      await reached(reach, made, ~binding=relayed.binding)
    | Some(_) | None =>
      Web.answered(
        ~status=404,
        `no binding ${Float.toString(relayed.binding)} is relayed for the organization`,
      )
    }
  | Operator | Host(_) | Nobody => Web.answered(~status=403, "a relay is an organization's alone")
  }

let stored = async (state: State.t, reach: Reach.t, ~caller, ~port, request, ~path) =>
  switch caller {
  | Access.Organization(organization) =>
    switch await state.storage(organization) {
    | Some({id, secret, address: Some(address)}) =>
      let made = Web.resent(`${reach.origin(~address, ~port)}${path}`, request)
      made
      ->Web.requestHeaders
      ->Web.setHeader("authorization", `Bearer ${Access.tokenText(id, secret)}`)
      await reached(reach, made, ~binding=id)
    | Some(_) | None =>
      Web.answered(~status=409, "the organization holds no binding its host bound here")
    }
  | Operator | Host(_) | Nobody => Web.answered(~status=403, "an object is an organization's alone")
  }
