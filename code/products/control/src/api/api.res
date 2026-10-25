module Contracts = Envelope.Contracts
module Calls = Serve.Calls
module Interface = Contracts.Interface

type parts = {
  state: State.t,
  artifacts: Artifacts.t,
  reach: Reach.t,
  tunnels: option<Tunnels.t>,
  standing: option<Standing.t>,
  driverPort: int,
  direct: Web.fetch,
  origin: string,
  wait: unit => promise<unit>,
}

let artifactBound = 33554432.

let tunnelName = id => `binding-${Float.toString(id)}`

/** An id drawn at random over 32 bits, 0 among them, which the state draws again, RFC b8f35. */
let random = () => Ids.ofBytes(Web.random(4))

let refused = (reason, message) => Calls.Refused({reason, message: Some(message)})
let denied = Calls.Refused({reason: "denied", message: None})

/** A label as a name of DNS writes one. */
let labeled = /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/

let organizations = (parts, caller: Access.caller) =>
  Calls.route({
    name: "organizations",
    fromJson: Interface.Organizations.fromJson,
    fromCbor: Interface.Organizations.fromCbor,
    reasons: [Interface.Organizations.open_],
    handle: async (_, {call}) =>
      switch (caller, call) {
      | (Operator, Open({label})) if labeled->RegExp.test(label) =>
        let {id, secret} = await parts.state.openOrganization(label, ~secret=Web.random(32))
        Output(
          Calls.output(
            ({organization: id, secret}: Contracts.OrganizationOpened.t),
            ~toJson=Contracts.OrganizationOpened.toJson,
            ~toCbor=Contracts.OrganizationOpened.toCbor,
          ),
        )
      | (Operator, Open(_)) =>
        refused("invalid", "a label is lowercase letters, digits and hyphens")
      | (Host(_) | Organization(_) | Nobody, _) => denied
      },
  })

let bound = (output: Contracts.BindingBound.t) => Calls.Output(
  Calls.output(
    output,
    ~toJson=Contracts.BindingBound.toJson,
    ~toCbor=Contracts.BindingBound.toCbor,
  ),
)

/** Why a binding is given no address, every one of the range held. */
let spent = id => `no address of 10.200.0.0/16 is left for binding ${Ids.text(id)}`

/** What answers a binding given no address, denied where its origin fixed its reach first, and
 * else unreachable, as a range spent frees as bindings close, monoflake/cloud's RFC vgvx6. */
let unaddressed = async (parts, id) =>
  switch await parts.state.binding(id) {
  | Some({origin: Some(_)}) => denied
  | Some(_) | None => refused("unreachable", spent(id))
  }

/** Why a tunnel was not given, no address taken for it or a step of Cloudflare's refused. */
type untunneled = Unaddressed | Unmade(string)

/**
 * A host's address taken, its tunnel made, the route to it and its token, each kept as it is made,
 * and the binding bound once its route is. The route is asked on every bind, one made before kept.
 */
let tunneled = async (parts, tunnels: Tunnels.t, binding: State.binding) =>
  switch await parts.state.addressed(~binding=binding.id) {
  | None => Error(Unaddressed)
  | Some(address) =>
    // No route can exist before its tunnel, so an address taken for a tunnel not made goes back.
    let given = async why => {
      if binding.address == None {
        await parts.state.unaddressed(~binding=binding.id, ~address)
      }
      Error(Unmade(why))
    }
    let tunnel = switch binding.tunnel {
    | Some(tunnel) => Ok(tunnel)
    | None =>
      switch await tunnels.make(tunnelName(binding.id)) {
      | Ok(tunnel) =>
        await parts.state.tunneled(~binding=binding.id, ~tunnel)
        Ok(tunnel)
      | Error(why) => Error(why)
      }
    }
    switch tunnel {
    | Error(why) => await given(why)
    | Ok(tunnel) =>
      switch await tunnels.route(~tunnel, ~address) {
      // A failed route keeps its address unbound, never another binding's while held, monoflake/cloud's
      // RFC vgvx6.
      | Error(why) => Error(Unmade(why))
      | Ok() =>
        await parts.state.routed(~binding=binding.id)
        (await tunnels.token(tunnel))
        ->Result.map(token => (address, token))
        ->Result.mapError(why => Unmade(why))
      }
    }
  }

/** A host bound by a tunnel, as rxmd9 binds one. */
let tunnelBound = async (parts, binding: State.binding) => {
  let id = binding.id
  let tunnelOf = (address, tunnel) => Contracts.BindingReached.Tunnel({address, ?tunnel})
  switch (parts.standing, parts.tunnels) {
  | (Some(standing), _) =>
    switch binding {
    | {bound: Some(_), address: Some(address)} =>
      bound({binding: id, reached: tunnelOf(address, binding.tunnel->Option.map(Web.utf8))})
    | {bound: None} | {address: None} =>
      switch await standing.reach() {
      | Ok({address, tunnel}) =>
        // An organization's own control keeps the tunnel's token itself, as it makes none.
        switch tunnel {
        | Some(tunnel) => await parts.state.tunneled(~binding=id, ~tunnel)
        | None => ()
        }
        // The address kept is answered, the first bind's in D1. Over objects, ordered within one
        // request alone, two binds at once may each be answered the one it gave.
        // The control stood on routed the reach it gave, so the binding is bound at once.
        switch await parts.state.addressed(~binding=id, ~address) {
        | Some(address) =>
          await parts.state.routed(~binding=id)
          bound({binding: id, reached: tunnelOf(address, tunnel->Option.map(Web.utf8))})
        | None => denied
        }
      | Error(why) => refused("unreachable", `the control stood on gave no reach, ${why}`)
      }
    }
  | (None, None) =>
    // With no tunnel to make the host is reached at its address directly, bound as it is taken.
    switch await parts.state.addressed(~binding=id) {
    | Some(address) =>
      await parts.state.routed(~binding=id)
      bound({binding: id, reached: tunnelOf(address, None)})
    | None => await unaddressed(parts, id)
    }
  | (None, Some(tunnels)) =>
    switch await tunneled(parts, tunnels, binding) {
    | Ok((address, token)) =>
      bound({binding: id, reached: tunnelOf(address, Some(Web.utf8(token)))})
    | Error(Unaddressed) => await unaddressed(parts, id)
    | Error(Unmade(why)) => refused("unreachable", `the host's tunnel could not be made, ${why}`)
    }
  }
}

/** Why an origin bind is refused once a tunnel fixed the binding's reach, 8j7b0. */
let tunneledFirst = id =>
  refused("invalid", `binding ${Ids.text(id)} is reached by its tunnel, and stays so`)

/** A last label naming no DNS name, as the parser leaves an IPv4 address. */
let numeric = /^(0x[0-9a-f]*|[0-9]+)$/

/** Names that never leave a machine or its own network, RFCs 6761, 6762 and 8375, and ICANN's. */
let local = ["localhost", "local", "internal", "home.arpa"]

/** RFC 3492's bias adapted after a code point is decoded. */
let adapt = (delta, ~points, ~first) => {
  let delta = ref(Math.floor(first ? delta /. 700. : delta /. 2.))
  delta := delta.contents +. Math.floor(delta.contents /. points)
  let k = ref(0.)
  while delta.contents > 35. *. 26. /. 2. {
    delta := Math.floor(delta.contents /. 35.)
    k := k.contents +. 36.
  }
  k.contents +. Math.floor(36. *. delta.contents /. (delta.contents +. 38.))
}

/** The code points a label's punycode after `xn--` decodes to, RFC 3492, or none. */
let decoded = encoded => {
  let length = String.length(encoded)
  let at = encoded->String.lastIndexOf("-")
  let out =
    encoded
    ->String.slice(~start=0, ~end=Math.Int.max(at, 0))
    ->String.split("")
    ->Array.filterMap(c => c->String.codePointAt(0))
  let (n, i, bias, pos, ok) = (ref(128.), ref(0.), ref(72.), ref(at + 1), ref(true))
  while ok.contents && pos.contents < length {
    let old = i.contents
    let (w, k, more) = (ref(1.), ref(36.), ref(true))
    while ok.contents && more.contents {
      let digit = switch encoded->String.codePointAt(pos.contents) {
      | Some(c) if c >= 48 && c <= 57 => c - 22
      | Some(c) if c >= 97 && c <= 122 => c - 97
      | Some(_) | None => -1
      }
      pos := pos.contents + 1
      if digit < 0 {
        ok := false
      } else {
        i := i.contents +. Int.toFloat(digit) *. w.contents
        let t = Math.max(1., Math.min(26., k.contents -. bias.contents))
        if Int.toFloat(digit) < t {
          more := false
        } else {
          w := w.contents *. (36. -. t)
          k := k.contents +. 36.
        }
        ok := ok.contents && i.contents <= 2147483647. && w.contents <= 2147483647.
      }
    }
    if ok.contents {
      let count = Int.toFloat(out->Array.length + 1)
      bias := adapt(i.contents -. old, ~points=count, ~first=old == 0.)
      n := n.contents +. Math.floor(i.contents /. count)
      i := i.contents -. Math.floor(i.contents /. count) *. count
      if n.contents > 1114111. || n.contents < 128. {
        ok := false
      } else {
        out->Array.splice(
          ~start=Float.toInt(i.contents),
          ~remove=0,
          ~insert=[Float.toInt(n.contents)],
        )
        i := i.contents +. 1.
      }
    }
  }
  ok.contents ? Some(String.fromCodePointMany(out)) : None
}

/** Whether a punycode label is the one the parser writes for what it decodes to. */
let canonical = label =>
  !(label->String.startsWith("xn--")) ||
  decoded(label->String.slice(~start=4))
  ->Option.flatMap(unicode => Web.parsed(`https://${unicode}.invalid`))
  ->Option.mapOr(false, url => url->Web.hostname->String.split(".")->Array.get(0) == Some(label))

/** An origin as 8j7b0 takes one, judged as the WHATWG parser leaves it, kept as `https://host`. */
let originOf = text =>
  Web.parsed(text)->Option.flatMap(url => {
    let host = url->Web.hostname
    let labels = host->String.split(".")
    let shaped =
      url->Web.protocol == "https:" &&
      url->Web.port == "" &&
      url->Web.username == "" &&
      url->Web.password == "" &&
      url->Web.pathname == "/" &&
      url->Web.search == "" &&
      url->Web.hash == ""
    let named =
      String.length(host) <= 253 &&
      labels->Array.length >= 2 &&
      labels->Array.every(l => labeled->RegExp.test(l) && canonical(l)) &&
      !(labels->Array.at(-1)->Option.mapOr(true, l => numeric->RegExp.test(l))) &&
      !(local->Array.some(name => host == name || host->String.endsWith(`.${name}`)))
    shaped && named ? Some(`https://${host}`) : None
  })

/** How long a call back to an origin is waited on, in milliseconds. */
let callBackDeadline = 10000

/** What Cloudflare's edge answers for an origin it could not reach, as the issuer reads them. */
let unreached = [521, 522, 523, 524, 530]

type proof = Proven | NotProven | Unreached | Unbuilt

/** Whether an origin answers its management's describe as the driver holding the token's hash. */
let proven = async (parts, ~origin, ~token) => {
  let reach = Reach.direct(origin, parts.direct)
  let call = Contracts.Interface.Management.toJson({call: Describe({}), capabilities: []})
  let request = () =>
    Web.request(
      `${reach.origin(~address=origin, ~port=443)}/management/describe`,
      {
        method: "POST",
        headers: dict{
          "authorization": `Bearer ${token}`,
          "content-type": "application/json",
          "accept": "application/json",
        },
        body: Web.utf8(JSON.stringify(call)),
        signal: Web.deadline(callBackDeadline),
      },
    )
  // A runtime refusing to build the request is refusing the origin, which is the caller's.
  switch request() {
  | exception JsExn(_) => Unbuilt
  | request =>
    switch await reach.fetch(request) {
    | exception JsExn(_) => Unreached
    | response if unreached->Array.includes(response->Web.status) => Unreached
    | response if response->Web.status != 200 => NotProven
    | response =>
      switch await response->Web.text {
      | exception JsExn(_) => Unreached
      | text =>
        switch JSON.parseOrThrow(text) {
        | exception JsExn(_) => NotProven
        | json =>
          switch Contracts.Answer.fromJson(json, Contracts.ManagementDescribed.fromJson) {
          | Ok(Success(_)) => Proven
          | Ok(Error(_)) | Error(_) => NotProven
          }
        }
      }
    }
  }
}

/** A host bound by its driver's origin, kept only once the origin's call back proves it. */
let originBound = async (parts, binding: State.binding, given) => {
  let id = binding.id
  let named = Ids.text(id)
  switch originOf(given) {
  | None =>
    refused("malformed", "an origin is https on a DNS name and its default port, and no more")
  | Some(origin) =>
    switch await proven(parts, ~origin, ~token=Access.tokenText(id, binding.secret)) {
    | Proven =>
      if await parts.state.originated(~binding=id, ~origin) {
        bound({binding: id, reached: Origin({origin: origin})})
      } else {
        // Another bind fixed its reach while this one was called back.
        switch await parts.state.binding(id) {
        | Some({bound: Some(_)}) => tunneledFirst(id)
        | Some(_) | None => denied
        }
      }
    | NotProven => refused("not_proven", `${origin} answered, and not as binding ${named}'s driver`)
    | Unreached => refused("unreachable", `${origin} did not answer binding ${named}'s call back`)
    | Unbuilt => refused("malformed", "the origin is no URL a request is sent to")
    }
  }
}

let bindings = (parts, caller: Access.caller) =>
  Calls.route({
    name: "bindings",
    fromJson: Interface.Bindings.fromJson,
    fromCbor: Interface.Bindings.fromCbor,
    reasons: [Interface.Bindings.open_, Interface.Bindings.bind],
    handle: async (_, {call}) =>
      switch (caller, call) {
      | (Operator, Open({organization})) =>
        if await parts.state.hasOrganization(organization) {
          let secret = Web.random(32)
          let binding = await parts.state.openBinding(
            ~organization,
            ~secret,
            ~relayed=false,
            ~random,
          )
          Output(
            Calls.output(
              ({binding, secret}: Contracts.BindingOpened.t),
              ~toJson=Contracts.BindingOpened.toJson,
              ~toCbor=Contracts.BindingOpened.toCbor,
            ),
          )
        } else {
          refused("not_found", `no organization ${Float.toString(organization)} is open`)
        }
      | (Host(id), Bind({reach})) =>
        switch (await parts.state.binding(id), reach) {
        | (None, _) => denied
        // An origin binding's token is spent by its first bind, so no bind moves it, 8j7b0.
        | (Some({origin: Some(_)}), _) => denied
        | (Some({bound: Some(_)}), Origin(_)) => tunneledFirst(id)
        | (Some(binding), Tunnel) => await tunnelBound(parts, binding)
        | (Some(binding), Origin({origin})) => await originBound(parts, binding, origin)
        }
      | (Operator | Organization(_) | Nobody, Bind(_))
      | (Host(_) | Organization(_) | Nobody, Open(_)) => denied
      },
  })

/** An address for an organization's own control, its tunnel made where this control makes them. */
let reaches = (parts, caller: Access.caller) =>
  Calls.route({
    name: "reaches",
    fromJson: Interface.Reaches.fromJson,
    fromCbor: Interface.Reaches.fromCbor,
    reasons: [Interface.Reaches.open_],
    handle: async (_, {call}) =>
      switch (caller, call) {
      | (Organization(organization), Open(_)) =>
        let id = await parts.state.openBinding(
          ~organization,
          ~secret=Web.random(32),
          ~relayed=true,
          ~random,
        )
        let opened = (output: Contracts.ReachOpened.t) => Calls.Output(
          Calls.output(
            output,
            ~toJson=Contracts.ReachOpened.toJson,
            ~toCbor=Contracts.ReachOpened.toCbor,
          ),
        )
        switch (parts.tunnels, await parts.state.binding(id)) {
        | (_, None) => refused("unreachable", `binding ${Ids.text(id)} was not kept`)
        | (None, Some(_)) =>
          switch await parts.state.addressed(~binding=id) {
          | Some(address) =>
            await parts.state.routed(~binding=id)
            opened({reach: id, address})
          | None => refused("no_address", spent(id))
          }
        | (Some(tunnels), Some(binding)) =>
          switch await tunneled(parts, tunnels, binding) {
          | Ok((address, token)) => opened({reach: id, address, tunnel: Web.utf8(token)})
          | Error(Unaddressed) => refused("no_address", spent(id))
          | Error(Unmade(why)) =>
            refused("unreachable", `the reach's tunnel could not be made, ${why}`)
          }
        }
      | (Operator | Host(_) | Nobody, _) => denied
      },
  })

let described = result =>
  switch result {
  | Ok(output) =>
    Calls.Output(
      Calls.output(
        output,
        ~toJson=Contracts.DeploymentDescribed.toJson,
        ~toCbor=Contracts.DeploymentDescribed.toCbor,
      ),
    )
  | Error({reason, message}: Driver.refused) => refused(reason, message)
  }

/** The host a binding's driver is reached at, or why it cannot be. */
let hostOf = async (parts, id) =>
  switch await parts.state.binding(id) {
  | None => Error(refused("not_found", `no binding ${Ids.text(id)} is open`))
  | Some({origin: Some(origin), secret}) =>
    Ok(
      (
        {
          reach: Reach.direct(origin, parts.direct),
          address: origin,
          port: parts.driverPort,
          token: Access.tokenText(id, secret),
        }: Driver.host
      ),
    )
  | Some({bound: None}) | Some({address: None}) =>
    Error(refused("unbound", `binding ${Ids.text(id)} has not been bound by its host`))
  | Some({bound: Some(_), address: Some(address), secret}) =>
    Ok(
      (
        {
          reach: parts.reach,
          address,
          port: parts.driverPort,
          token: Access.tokenText(id, secret),
        }: Driver.host
      ),
    )
  }

let put = async (parts, input: Contracts.ReleasePut.t) => {
  let size = input.artifact->TypedArray.length->Int.toFloat
  if size > artifactBound {
    refused("too_large", `an artifact holds ${Float.toString(artifactBound)} bytes at most`)
  } else {
    let hash = await Web.sha256(input.artifact)
    let hex = Envelope.Hex.encode(hash)
    await parts.artifacts.put(hex, input.artifact)
    await parts.state.putRelease({hash: hex, form: input.form, size})
    Output(
      Calls.output(
        ({hash, size}: Contracts.ReleaseHeld.t),
        ~toJson=Contracts.ReleaseHeld.toJson,
        ~toCbor=Contracts.ReleaseHeld.toCbor,
      ),
    )
  }
}

/** A refusal's message naming the app drawn for it, `app <8 hex>, ` before what it says. */
let naming = (app, message) => `app ${Ids.text(app)}, ${message}`

/** Thrown where a deploy's container is declared for an app forgotten since it began. */
exception Forgotten

let undeployed = app => refused("not_found", `no app ${Ids.text(app)} is deployed`)

/**
 * The release deployed as the app given, one the control deployed before, or as a new app whose
 * id the control draws, so no caller makes an id, RFC b8f35.
 */
let deploy = async (parts, input: Contracts.ReleaseDeploy.t) => {
  let hex = Envelope.Hex.encode(input.release)
  let unknown = switch input.app {
  | Some(app) => (await parts.state.deployment(app))->Option.isNone ? Some(app) : None
  | None => None
  }
  switch unknown {
  | Some(app) => undeployed(app)
  | None =>
    switch (await hostOf(parts, input.binding), await parts.state.release(hex)) {
    | (Error(answer), _) => answer
    | (Ok(_), None) => refused("not_found", `no release ${hex} is kept`)
    | (Ok(host), Some(release)) =>
      let (app, drawn) = switch input.app {
      | Some(app) => (app, false)
      | None =>
        let app = await parts.state.drawApp(~random)
        // Kept before the host is called, its container 0 for none yet, so a deploy that fails
        // is retried under this id.
        await parts.state.deploy({app, binding: input.binding, release: hex, capacity: 0.})
        (app, true)
      }
      // A container declared for an app forgotten meanwhile is kept nowhere, so its host is not
      // asked to run it.
      let declared = async capacity => {
        await parts.state.deploy({app, binding: input.binding, release: hex, capacity})
        if (await parts.state.deployment(app))->Option.isNone {
          throw(Forgotten)
        }
      }
      let answer = switch await Deploying.deployed(
        host,
        ~app,
        ~hash=input.release,
        ~form=release.form,
        ~address=`${parts.origin}/artifacts/${hex}`,
        ~secrets=input.secrets->Option.getOr(dict{}),
        ~network=input.network->Option.getOr([]),
        ~declared,
        ~wait=parts.wait,
      ) {
      | answer => answer
      | exception Forgotten =>
        Error({
          reason: "not_found",
          message: `app ${Ids.text(app)} was forgotten as it was deployed`,
        })
      }
      described(
        drawn ? answer->Result.mapError(r => {...r, message: naming(app, r.message)}) : answer,
      )
    }
  }
}

let describe = async (parts, app) =>
  switch await parts.state.deployment(app) {
  | None => undeployed(app)
  | Some(deployment) =>
    switch await hostOf(parts, deployment.binding) {
    | Error(answer) => answer
    | Ok(host) => described(await Deploying.described(host, ~app))
    }
  }

/**
 * An app whose id was drawn and that never ran removed, one that ran refused as `deployed`, and an
 * id the control does not hold as `not_found`.
 */
let forget = async (parts, app) => {
  let ran = () =>
    refused("deployed", `app ${Ids.text(app)} has run, so it is removed by its own path`)
  switch await parts.state.deployment(app) {
  | Some({capacity}) if capacity != 0. => ran()
  | Some(_) | None =>
    if await parts.state.forgetApp(app) {
      Output(
        Calls.output(
          ({app: app}: Contracts.ReleaseOf.t),
          ~toJson=Contracts.ReleaseOf.toJson,
          ~toCbor=Contracts.ReleaseOf.toCbor,
        ),
      )
    } else {
      // A deploy may have declared its container since it was read.
      switch await parts.state.deployment(app) {
      | Some(_) => ran()
      | None => refused("not_found", `no app ${Ids.text(app)} is held`)
      }
    }
  }
}

let releases = (parts, caller: Access.caller) =>
  Calls.route({
    name: "releases",
    fromJson: Interface.Releases.fromJson,
    fromCbor: Interface.Releases.fromCbor,
    reasons: [
      Interface.Releases.put,
      Interface.Releases.deploy,
      Interface.Releases.describe,
      Interface.Releases.forget,
    ],
    handle: async (_, {call}) =>
      switch (caller, call) {
      | (Operator, Put(input)) => await put(parts, input)
      | (Operator, Deploy(input)) => await deploy(parts, input)
      | (Operator, Describe({app})) => await describe(parts, app)
      | (Operator, Forget({app})) => await forget(parts, app)
      | (Host(_) | Organization(_) | Nobody, _) => denied
      },
  })

let routes = (parts, caller) => [
  organizations(parts, caller),
  bindings(parts, caller),
  reaches(parts, caller),
  releases(parts, caller),
]
