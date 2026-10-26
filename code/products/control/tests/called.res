/***
 * The API called in memory as each caller would call it, its host faked, shared by the API's tests.
 */
module Contracts = Envelope.Contracts
module Calls = Serve.Calls

let untrusted = (): Capability.Signed.trust => {
  root: Uint8Array.fromLength(32),
  certificates: [],
  now: 0.,
}

type stood = {parts: Api.parts, host: Host.t, artifacts: dict<Uint8Array.t>}

/** A fetch for origins that no test reaches. */
let nowhere: Web.fetch = async _ => JsError.throwWithMessage("no origin is reached here")

let stand = (~tunnels=?, ~standing=?, ~direct=nowhere) => {
  let host = Host.make()
  let (artifacts, held) = Memory.artifacts()
  {
    parts: {
      state: Memory.state(),
      artifacts,
      reach: host.reach,
      tunnels,
      standing,
      driverPort: 37483,
      direct,
      origin: "https://control.test",
      wait: async () => (),
    },
    host,
    artifacts: held,
  }
}

/** A call made as a caller, its answer read as JSON. */
let called = async (stood, caller, envelope) => {
  let named = key =>
    envelope
    ->JSON.Decode.object
    ->Option.flatMap(o => o->Dict.get(key))
    ->Option.flatMap(JSON.Decode.string)
    ->Option.getOr("")
  let answer = await Calls.serve(
    Api.routes(stood.parts, caller),
    ~trust=untrusted,
    {
      method_: "POST",
      path: `/${named("interface")}/${named("operation")}`,
      contentType: Some("application/json"),
      accept: Some("application/json"),
      body: Web.utf8(JSON.stringify(envelope)),
    },
  )
  (answer.status, JSON.parseOrThrow(Web.fromUtf8(answer.body)))
}

let organizations = call => Contracts.Interface.Organizations.toJson({call, capabilities: []})
let bindings = call => Contracts.Interface.Bindings.toJson({call, capabilities: []})
let releases = call => Contracts.Interface.Releases.toJson({call, capabilities: []})
let reaches = call => Contracts.Interface.Reaches.toJson({call, capabilities: []})

let member = (json, name) =>
  json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(name))->Option.getOr(JSON.Null)
let data = json => json->member("data")
let reason = json => json->member("reason")->JSON.Decode.string

let artifact = Web.utf8("a bundle")

/** The binding opened for an organization, its id as the control drew it. */
let openBinding = async (stood, organization) => {
  let (_, opened) = await called(stood, Operator, bindings(Open({organization: organization})))
  opened->data->member("binding")->JSON.Decode.float->Option.getOr(0.)
}

/** An organization, a bound binding and a release, as the operator and the host make them. */
let opened = async stood => {
  let (_, org) = await called(stood, Operator, organizations(Open({label: "first"})))
  let organization = org->data->member("organization")->JSON.Decode.float->Option.getOr(0.)
  let (_, binding) = await called(stood, Operator, bindings(Open({organization: organization})))
  let id = binding->data->member("binding")->JSON.Decode.float->Option.getOr(0.)
  ignore(await called(stood, Host(id), bindings(Bind({reach: Tunnel}))))
  let (_, put) = await called(stood, Operator, releases(Put({form: Modules, artifact})))
  let hash = put->data->member("hash")->JSON.Decode.string->Option.getOr("")
  (id, hash)
}

/** The app a deploy answered it runs. */
let ranAs = answer => answer->data->member("runs")->member("id")->JSON.Decode.float

/** The app a refusal names as drawn for the deploy it refused, `app <8 hex>, ` first. */
let named = answer =>
  switch answer->member("message")->JSON.Decode.string {
  | Some(message) if /^app [0-9a-f]{8}, /->RegExp.test(message) =>
    Ids.ofText(message->String.slice(~start=4, ~end=12))
  | Some(_) | None => None
  }

/** Tunnels faked, counting what each made. */
let tunnels = (~failing=false, ~unrouted=0) => {
  let made = ref(0)
  let routes = []
  let faked: Tunnels.t = {
    make: async name => {
      made := made.contents + 1
      failing ? Error("the API could not be reached") : Ok(`tunnel-${name}`)
    },
    route: async (~tunnel, ~address) => {
      routes->Array.push((tunnel, address))
      // The first `unrouted` routes asked are refused.
      routes->Array.length <= unrouted ? Error("the route conflicts with another") : Ok()
    },
    token: async tunnel => Ok(`token of ${tunnel}`),
  }
  (faked, made, routes)
}

/** The states the API keeps, each fresh, in memory, in D1 and over objects. */
let kept = () => {
  let sealing = Sealing.ofKey(Some(Envelope.Base64url.encode(Web.random(32))))
  let held: dict<Uint8Array.t> = dict{}
  let objects: Objects.t = {
    write: async (name, bytes) => Ok(held->Dict.set(name, bytes)),
    read: async name => Ok(held->Dict.get(name)),
    list: async prefix => Ok(
      held
      ->Dict.keysToArray
      ->Array.filter(n => n->String.startsWith(prefix))
      ->Array.toSorted(String.compare),
    ),
    delete: async name => Ok(held->Dict.delete(name)),
  }
  [
    ("memory", Memory.state()),
    ("D1", State.ofDatabase(Sqlite.database(), ~sealing)),
    ("objects", State.ofObjects(objects, ~sealing)),
  ]
}

/** The paths asked of the host since a count of what it was asked. */
let askedSince = (stood, seen) =>
  stood.host.seen
  ->Array.slice(~start=seen)
  ->Array.map(s => Web.parts(s.url)->Web.pathname)

/** A refusal's reason and message. */
let refusal = ((_, answer)) => (
  answer->reason,
  answer->member("message")->JSON.Decode.string->Option.getOr(""),
)
