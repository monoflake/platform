module State = ControlOrganization.State
module Ids = ControlOrganization.Ids
module Addresses = ControlOrganization.Addresses
module Artifacts = ControlOrganization.Artifacts
module Web = ControlOrganization.Web

/*** The control's parts kept in memory, as the API's tests stand them in for D1 and R2. */

/** Draws counting up from the floor, the first id a draw may give. */
let counting = () => {
  let n = ref(Ids.floor -. 1.)
  () => {
    n := n.contents +. 1.
    n.contents
  }
}

let state = (): State.t => {
  let organizations: dict<State.organization> = dict{}
  let bindings: dict<State.binding> = dict{}
  let releases: dict<State.release> = dict{}
  let deployments: dict<State.deployment> = dict{}
  let apps = []
  let key = Float.toString
  let change = (id, f) =>
    bindings->Dict.get(key(id))->Option.forEach(b => bindings->Dict.set(key(id), f(b)))
  {
    openOrganization: async (label, ~secret) =>
      switch organizations->Dict.get(label) {
      | Some(organization) => organization
      | None =>
        let id = organizations->Dict.keysToArray->Array.length->Int.toFloat +. 1.
        organizations->Dict.set(label, {id, secret})
        {id, secret}
      },
    hasOrganization: async id => organizations->Dict.valuesToArray->Array.some(o => o.id == id),
    organizationSecret: async id =>
      organizations->Dict.valuesToArray->Array.find(o => o.id == id)->Option.map(o => o.secret),
    openBinding: (~organization, ~secret, ~relayed, ~random) =>
      Ids.drawn(~random, ~kind="binding", async id => {
        let held =
          apps->Array.includes(id) ||
          bindings->Dict.has(key(id)) ||
          organizations->Dict.valuesToArray->Array.some(o => o.id == id) ||
          deployments->Dict.has(key(id))
        if !held {
          bindings->Dict.set(
            key(id),
            {
              id,
              organization,
              secret,
              tunnel: None,
              address: None,
              origin: None,
              relayed,
              bound: None,
            },
          )
        }
        !held
      }),
    binding: async id => bindings->Dict.get(key(id)),
    storage: async organization =>
      bindings
      ->Dict.valuesToArray
      ->Array.filter(b =>
        b.organization == organization && !b.relayed && b.bound != None && b.origin == None
      )
      ->Array.toSorted((a, b) => a.bound->Option.getOr(0.) -. b.bound->Option.getOr(0.))
      ->Array.get(0),
    addressedAt: async address =>
      bindings->Dict.valuesToArray->Array.find(b => b.address == Some(address)),
    tunneled: async (~binding, ~tunnel) => change(binding, b => {...b, tunnel: Some(tunnel)}),
    addressed: async (~binding, ~address=?) =>
      switch bindings->Dict.get(key(binding)) {
      | Some({address: Some(held)}) => Some(held)
      | Some(b) if b.origin == None =>
        let chosen = switch address {
        | Some(given) => Some(given)
        | None => Addresses.lowest(bindings->Dict.valuesToArray->Array.filterMap(b => b.address))
        }
        chosen->Option.forEach(address =>
          bindings->Dict.set(key(binding), {...b, address: Some(address)})
        )
        chosen
      | Some(_) | None => None
      },
    unaddressed: async (~binding, ~address) =>
      switch bindings->Dict.get(key(binding)) {
      | Some(b) if b.address == Some(address) && b.bound == None =>
        bindings->Dict.set(key(binding), {...b, address: None})
      | Some(_) | None => ()
      },
    routed: async (~binding) =>
      switch bindings->Dict.get(key(binding)) {
      | Some({address: Some(_), bound: None, origin: None} as b) =>
        let order =
          bindings->Dict.valuesToArray->Array.filterMap(b => b.bound)->Array.reduce(0., Math.max)
        bindings->Dict.set(key(binding), {...b, bound: Some(order +. 1.)})
      | Some(_) | None => ()
      },
    originated: async (~binding, ~origin) =>
      switch bindings->Dict.get(key(binding)) {
      | Some(b) if b.origin == None && b.bound == None =>
        bindings->Dict.set(key(binding), {...b, origin: Some(origin)})
        true
      | Some(_) | None => false
      },
    putRelease: async release =>
      if releases->Dict.get(release.hash) == None {
        releases->Dict.set(release.hash, release)
      },
    release: async hash => releases->Dict.get(hash),
    deploy: async d =>
      switch (apps->Array.includes(d.app), deployments->Dict.get(key(d.app))) {
      | (true, _) => deployments->Dict.set(key(d.app), d)
      | (false, Some(held)) if State.ran(held) => deployments->Dict.set(key(d.app), d)
      | (false, Some(_) | None) => ()
      },
    deployment: async app => deployments->Dict.get(key(app)),
    drawApp: (~random) =>
      Ids.drawn(~random, ~kind="app", async id => {
        let held =
          apps->Array.includes(id) ||
          bindings->Dict.has(key(id)) ||
          organizations->Dict.valuesToArray->Array.some(o => o.id == id) ||
          deployments->Dict.has(key(id))
        if !held {
          apps->Array.push(id)
        }
        !held
      }),
    forgetApp: async app =>
      switch (apps->Array.indexOf(app), deployments->Dict.get(key(app))) {
      | (_, Some(held)) if State.ran(held) => false
      | (-1, None) => false
      | (at, _) =>
        if at >= 0 {
          apps->Array.splice(~start=at, ~remove=1, ~insert=[])
        }
        deployments->Dict.delete(key(app))
        true
      },
    hasApp: async app => apps->Array.includes(app),
    retireApp: async app => {
      switch apps->Array.indexOf(app) {
      | -1 => ()
      | at => apps->Array.splice(~start=at, ~remove=1, ~insert=[])
      }
      deployments->Dict.delete(key(app))
    },
  }
}

/** Artifacts kept in memory, and the hashes put. */
let artifacts = (): (Artifacts.t, dict<Uint8Array.t>) => {
  let held = dict{}
  (
    {
      put: async (hash, bytes) => held->Dict.set(hash, bytes),
      served: async hash =>
        held
        ->Dict.get(hash)
        ->Option.map(bytes =>
          Web.response(
            bytes,
            {status: 200, headers: dict{"content-type": "application/octet-stream"}},
          )
        ),
    },
    held,
  )
}
