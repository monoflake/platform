module Contracts = Envelope.Contracts
module Calls = Serve.Calls
module Interface = Contracts.Interface

type parts = {
  state: State.t,
  artifacts: Artifacts.t,
  reach: Reach.t,
  tunnels: option<Tunnels.t>,
  driverPort: int,
  origin: string,
  wait: unit => promise<unit>,
}

let artifactBound = 33554432.

let addressOf = id => {
  let n = id->Float.toInt
  `10.200.${Int.toString(n / 256)}.${Int.toString(mod(n, 256))}`
}

let tunnelName = id => `binding-${Float.toString(id)}`

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

/** A host's tunnel made, its route to the host's address and its token, each kept as it is made. */
let tunneled = async (parts, tunnels: Tunnels.t, binding: State.binding, address) => {
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
  | Error(why) => Error(why)
  | Ok(tunnel) =>
    let routed = switch binding.address {
    | Some(_) => Ok()
    | None =>
      switch await tunnels.route(~tunnel, ~address) {
      | Ok() =>
        await parts.state.addressed(~binding=binding.id, ~address)
        Ok()
      | Error(why) => Error(why)
      }
    }
    switch routed {
    | Ok() => await tunnels.token(tunnel)
    | Error(why) => Error(why)
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
          let binding = await parts.state.openBinding(~organization, ~secret, ~relayed=false)
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
      | (Host(id), Bind(_)) =>
        switch await parts.state.binding(id) {
        | None => denied
        | Some(binding) =>
          let address = addressOf(id)
          switch parts.tunnels {
          | None =>
            if binding.address == None {
              await parts.state.addressed(~binding=id, ~address)
            }
            bound({binding: id, address})
          | Some(tunnels) =>
            switch await tunneled(parts, tunnels, binding, address) {
            | Ok(token) => bound({binding: id, address, tunnel: Web.utf8(token)})
            | Error(why) => refused("unreachable", `the host's tunnel could not be made, ${why}`)
            }
          }
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
        let id = await parts.state.openBinding(~organization, ~secret=Web.random(32), ~relayed=true)
        let address = addressOf(id)
        let opened = (output: Contracts.ReachOpened.t) => Calls.Output(
          Calls.output(
            output,
            ~toJson=Contracts.ReachOpened.toJson,
            ~toCbor=Contracts.ReachOpened.toCbor,
          ),
        )
        switch (parts.tunnels, await parts.state.binding(id)) {
        | (_, None) => refused("unreachable", `binding ${Float.toString(id)} was not kept`)
        | (None, Some(_)) =>
          await parts.state.addressed(~binding=id, ~address)
          opened({reach: id, address})
        | (Some(tunnels), Some(binding)) =>
          switch await tunneled(parts, tunnels, binding, address) {
          | Ok(token) => opened({reach: id, address, tunnel: Web.utf8(token)})
          | Error(why) => refused("unreachable", `the reach's tunnel could not be made, ${why}`)
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
  | None => Error(refused("not_found", `no binding ${Float.toString(id)} is open`))
  | Some({address: None}) =>
    Error(refused("unbound", `binding ${Float.toString(id)} has not been bound by its host`))
  | Some({address: Some(address), secret}) =>
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

let deploy = async (parts, input: Contracts.ReleaseDeploy.t) => {
  let hex = Envelope.Hex.encode(input.release)
  switch (await hostOf(parts, input.binding), await parts.state.release(hex)) {
  | (Error(answer), _) => answer
  | (Ok(_), None) => refused("not_found", `no release ${hex} is kept`)
  | (Ok(host), Some(release)) =>
    described(
      await Deploying.deployed(
        host,
        ~app=input.app,
        ~hash=input.release,
        ~form=release.form,
        ~address=`${parts.origin}/artifacts/${hex}`,
        ~secrets=input.secrets->Option.getOr(dict{}),
        ~network=input.network->Option.getOr([]),
        ~declared=capacity =>
          parts.state.deploy({app: input.app, binding: input.binding, release: hex, capacity}),
        ~wait=parts.wait,
      ),
    )
  }
}

let describe = async (parts, app) =>
  switch await parts.state.deployment(app) {
  | None => refused("not_found", `no app ${Float.toString(app)} is deployed`)
  | Some(deployment) =>
    switch await hostOf(parts, deployment.binding) {
    | Error(answer) => answer
    | Ok(host) => described(await Deploying.described(host, ~app))
    }
  }

let releases = (parts, caller: Access.caller) =>
  Calls.route({
    name: "releases",
    fromJson: Interface.Releases.fromJson,
    fromCbor: Interface.Releases.fromCbor,
    reasons: [Interface.Releases.put, Interface.Releases.deploy, Interface.Releases.describe],
    handle: async (_, {call}) =>
      switch (caller, call) {
      | (Operator, Put(input)) => await put(parts, input)
      | (Operator, Deploy(input)) => await deploy(parts, input)
      | (Operator, Describe({app})) => await describe(parts, app)
      | (Host(_) | Organization(_) | Nobody, _) => denied
      },
  })

let routes = (parts, caller) => [
  organizations(parts, caller),
  bindings(parts, caller),
  reaches(parts, caller),
  releases(parts, caller),
]
