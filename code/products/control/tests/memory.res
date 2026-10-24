/*** The control's parts kept in memory, as the API's tests stand them in for D1 and R2. */
let state = (): State.t => {
  let organizations: dict<State.organization> = dict{}
  let bindings: dict<State.binding> = dict{}
  let releases: dict<State.release> = dict{}
  let deployments: dict<State.deployment> = dict{}
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
    openBinding: async (~organization, ~secret, ~relayed) => {
      let id = bindings->Dict.keysToArray->Array.length->Int.toFloat +. 1.
      bindings->Dict.set(key(id), {id, organization, secret, tunnel: None, address: None, relayed})
      id
    },
    binding: async id => bindings->Dict.get(key(id)),
    storage: async organization =>
      bindings
      ->Dict.valuesToArray
      ->Array.filter(b => b.organization == organization && !b.relayed && b.address != None)
      ->Array.toSorted((a, b) => a.id -. b.id)
      ->Array.get(0),
    tunneled: async (~binding, ~tunnel) => change(binding, b => {...b, tunnel: Some(tunnel)}),
    addressed: async (~binding, ~address) => change(binding, b => {...b, address: Some(address)}),
    putRelease: async release =>
      if releases->Dict.get(release.hash) == None {
        releases->Dict.set(release.hash, release)
      },
    release: async hash => releases->Dict.get(hash),
    deploy: async d => deployments->Dict.set(key(d.app), d),
    deployment: async app => deployments->Dict.get(key(app)),
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
