module Contracts = Envelope.Contracts

let capacity: Contracts.ManagementCapacity.t = Container({millicores: 500., memory: 268435456.})

type planned =
  | Held({into: float})
  | Apply({list: Contracts.ManagementApply.t, into: float})

let isContainer = (capacity: Contracts.ManagementCapacity.t) =>
  switch capacity {
  | Container(_) => true
  | Volume(_) | Object(_) | Database(_) => false
  }

let isAsked = (state: Contracts.ManagementState.t) =>
  switch state {
  | Making | Made(_) | Failed(_) => true
  | Unasked(_) => false
  }

let planned = (described: Contracts.ManagementDescribed.t, ~credential) => {
  let asked = described.items->Array.filter(i => isAsked(i.state))
  switch (asked->Array.find(i => isContainer(i.capacity)), asked) {
  | (Some(held), _) => Ok(Held({into: held.id}))
  | (None, []) =>
    // An id past every one the binding holds, an unasked one's too, so none is taken again.
    let into = described.items->Array.reduce(0., (most, i) => Math.max(most, i.id)) +. 1.
    Ok(
      Apply({
        list: {
          generation: described.generation +. 1.,
          items: [{id: into, capacity, credentials: [credential]}],
        },
        into,
      }),
    )
  | (None, others) =>
    Error(
      `the binding asks ${others
        ->Array.map(i => Float.toString(i.id))
        ->Array.join(
          ", ",
        )} and no container, and describe gives no item's credentials to keep them`,
    )
  }
}

let deploy = (~app, ~hash, ~form, ~address, ~into): Contracts.DeploymentDeploy.t => {
  runs: App({id: app}),
  version: hash,
  form,
  isolation: [Isolate],
  artifact: {address, hash},
  // No footing is built yet, so the address is one that answers nothing.
  footing: "https://footing.invalid",
  secrets: dict{},
  network: [],
  into,
}

let management = call => Contracts.Interface.Management.toJson({call, capabilities: []})
let deployments = call => Contracts.Interface.Deployments.toJson({call, capabilities: []})

let describeList = host =>
  Driver.call(host, management(Describe({})), Contracts.ManagementDescribed.fromJson)

let invalid = (message): Driver.refused => {reason: "invalid", message}

/** Asked again while the container is made, a minute at most at the pace `wait` keeps. */
let rec made = async (host, into, ~wait, ~left=240) =>
  switch await describeList(host) {
  | Error(refused) => Error(refused)
  | Ok(described) =>
    switch described.items->Array.find(i => i.id == into) {
    | Some({state: Made(_)}) => Ok()
    | Some({state: Making}) if left > 0 =>
      await wait()
      await made(host, into, ~wait, ~left=left - 1)
    | Some({state: Making}) =>
      Error({reason: "unreachable", message: "no container after a minute"})
    | Some({state: Failed({reason, ?message})}) =>
      Error(invalid(message->Option.mapOr(reason, m => `${reason}, ${m}`)))
    | Some({state: Unasked(_)}) | None =>
      Error(invalid(`container ${Float.toString(into)} is no longer asked`))
    }
  }

/** The binding's container for apps, asked for and made where none is. */
let container = async (host, ~wait) =>
  switch await describeList(host) {
  | Error(refused) => Error(refused)
  | Ok(described) =>
    switch planned(described, ~credential=Web.random(32)) {
    | Error(why) => Error(invalid(why))
    | Ok(Held({into})) => (await made(host, into, ~wait))->Result.map(() => into)
    | Ok(Apply({list, into})) =>
      switch await Driver.call(host, management(Apply(list)), Contracts.ManagementHeld.fromJson) {
      | Error(refused) => Error(refused)
      | Ok(_) => (await made(host, into, ~wait))->Result.map(() => into)
      }
    }
  }

let deployed = async (host, ~app, ~hash, ~form, ~address, ~declared, ~wait) =>
  switch await container(host, ~wait) {
  | Error(refused) => Error(refused)
  | Ok(into) =>
    await declared(into)
    await Driver.call(
      host,
      deployments(Deploy(deploy(~app, ~hash, ~form, ~address, ~into))),
      Contracts.DeploymentDescribed.fromJson,
    )
  }

let described = (host, ~app) =>
  Driver.call(
    host,
    deployments(Describe({runs: App({id: app})})),
    Contracts.DeploymentDescribed.fromJson,
  )
