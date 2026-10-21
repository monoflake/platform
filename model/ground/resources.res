/**
 * What each host's driver gives and what a footing and the products ask of it, RFC vr5lw, checked
 * at every step of the path.
 */
type class = [#compute | #storage | #database]

/**
 * A kind of what a resource gives, each a contract with an implementation a driver,
 * `model/ground/drivers.res`; a database's sizes are open [C23].
 */
type kind = [#function | #instance | #container | #object | #volume | #database]

let classOf = (k: kind): class =>
  switch k {
  | #function | #instance | #container => #compute
  | #object | #volume => #storage
  | #database => #database
  }

/**
 * A network a resource may be in, the public one, Cloudflare's by a tunnel, or a relay's, RFC
 * vr5lw.
 */
type network = [#public | #cloudflare | #relay]

type resource = {
  gives: array<kind>,
  /** The networks it is in, one in two being a jump between them. */
  in_: array<network>,
  /** The private networks it stands up, which it is a jump into from the public one. */
  stands?: array<network>,
  /**
   * The CPU a call may take on each of the vendor's plans in milliseconds, docs/lessons/. A
   * machine's limit is open [D8].
   */
  cpu?: {free: float, paid: float},
  /** Whether it is used only once metering holds, being priced by use, RFC 94y0d. */
  metered?: bool,
  from: string,
}

let resources: dict<resource> = dict{
  /* A machine with an address, a database its driver makes of a container and a volume. */
  "machine": {
    gives: [#function, #instance, #container, #object, #volume, #database],
    in_: [#public, #cloudflare, #relay],
    stands: [#relay],
    from: "vr5lw",
  },
  "machine at home": {
    gives: [#function, #instance, #container, #object, #volume, #database],
    in_: [#cloudflare, #relay],
    from: "vr5lw",
  },
  /* Its `in_` is Cloudflare's edge, which a Worker stands for here. */
  "worker": {
    gives: [#function],
    cpu: {free: 10., paid: 300_000.},
    in_: [#public, #cloudflare],
    stands: [#cloudflare],
    from: "vr5lw, b8f35",
  },
  "durable object": {
    gives: [#instance, #database],
    metered: true,
    in_: [#cloudflare],
    from: "vr5lw, 94y0d",
  },
  /* Reached at the adapter its driver deploys, which is its address, vr5lw. */
  "d1": {gives: [#database], in_: [#public, #cloudflare], from: "vr5lw"},
  "r2": {gives: [#object], in_: [#public, #cloudflare], from: "vr5lw"},
  /* Another platform's three products, given through the driver's interface, 94y0d. */
  "platform products": {
    gives: [#function, #instance, #container, #object, #database],
    in_: [#public],
    from: "vr5lw, 94y0d",
  },
}

/** The resources each ground of `model/bootstrap/steps.res` holds. */
let groundOf = (g: Steps.ground) =>
  switch g {
  | #cloudflare => ["worker", "durable object", "d1", "r2"]
  | #provider => ["machine"]
  | #home => ["machine at home"]
  | #platform => ["platform products"]
  }

/**
 * The CPU cutting and sealing a parcel takes in a call, assumed at 100 milliseconds until measured.
 */
let assumedSealCpu = 100.

type need = {any: array<kind>, cpu?: float, why: string}

/**
 * What the products ask of an organization's extensions in v0, each need met by any of its kinds,
 * RFCs 49qyg and vuanj.
 */
let needs: array<need> = [
  {any: [#function], why: "compute runs an app's derive and effect"},
  {
    any: [#function],
    cpu: assumedSealCpu,
    why: "the storage cuts and seals up to 16 MiB in a call, b8f35",
  },
  {
    any: [#database, #instance],
    why: "the database product needs a database, or an instance to write a tablet",
  },
  {any: [#object], why: "storage keeps buckets, and a tablet archives its log and snapshots"},
]

let get = (d, k) => Dict.get(d, k)->Option.getOrThrow

let resourcesOf = (d: Steps.deployment) =>
  d.ground->Array.flatMap(groundOf)->Array.map(n => (n, get(resources, n)))

/** What of a deployment's resources reaches the public network by no path, vr5lw. */
let unreached = (d: Steps.deployment): array<string> => {
  let all = resourcesOf(d)
  let standing = Set.fromArray(
    Array.concat([#public], all->Array.flatMap(((_, r)) => r.stands->Option.getOr([]))),
  )
  let reached = Set.fromArray([#public])
  let grew = ref(true)
  while grew.contents {
    grew := false
    all->Array.forEach(((_, r)) => {
      let nets = r.in_->Array.filter(n => standing->Set.has(n))
      if nets->Array.some(n => reached->Set.has(n)) {
        nets->Array.forEach(n =>
          if !(reached->Set.has(n)) {
            reached->Set.add(n)
            grew := true
          }
        )
      }
    })
  }
  all
  ->Array.filter(((_, r)) => !(r.in_->Array.some(n => reached->Set.has(n) && standing->Set.has(n))))
  ->Array.map(((n, _)) => n)
}

let usable = (r: resource, d: Steps.deployment) =>
  !(r.metered->Option.getOr(false)) || d.on->Array.includes(#metering)

/** What a deployment's footing may hold, anything its ground gives but the paid plan. */
let footingKinds = (d: Steps.deployment): Set.t<kind> =>
  Set.fromArray(
    d.ground
    ->Array.flatMap(groundOf)
    ->Array.map(n => get(resources, n))
    ->Array.filter(r => usable(r, d))
    ->Array.flatMap(r => r.gives),
  )

/** What a deployment's extensions may give, compute, storage and databases, each kind with the
 * most CPU a call may take of it on the deployment's plan. */
let extensionKinds = (d: Steps.deployment): Map.t<kind, float> => {
  let given = Map.make()
  resourcesOf(d)
  ->Array.filter(((_, r)) => usable(r, d))
  ->Array.forEach(((_, r)) => {
    let cpu = switch r.cpu {
    | Some(c) =>
      switch d.plan->Option.getOr(#free) {
      | #free => c.free
      | #paid => c.paid
      }
    | None => Float.Constants.positiveInfinity
    }
    r.gives->Array.forEach(k =>
      given->Map.set(k, Math.max(given->Map.get(k)->Option.getOr(0.), cpu))
    )
  })
  given
}
