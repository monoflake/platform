/*** The control's parts kept in memory, as the API's tests stand them in for D1 and R2. */
let state = (): State.t => {
  let organizations: dict<float> = dict{}
  let bindings: dict<State.binding> = dict{}
  let releases: dict<State.release> = dict{}
  let deployments: dict<State.deployment> = dict{}
  let key = Float.toString
  let change = (id, f) =>
    bindings->Dict.get(key(id))->Option.forEach(b => bindings->Dict.set(key(id), f(b)))
  {
    openOrganization: async label =>
      switch organizations->Dict.get(label) {
      | Some(id) => id
      | None =>
        let id = organizations->Dict.keysToArray->Array.length->Int.toFloat +. 1.
        organizations->Dict.set(label, id)
        id
      },
    hasOrganization: async id => organizations->Dict.valuesToArray->Array.includes(id),
    openBinding: async (~organization, ~secret) => {
      let id = bindings->Dict.keysToArray->Array.length->Int.toFloat +. 1.
      bindings->Dict.set(key(id), {id, organization, secret, tunnel: None, address: None})
      id
    },
    binding: async id => bindings->Dict.get(key(id)),
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
