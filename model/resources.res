/**
 * What each host's driver gives, RFC vr5lw, and what a footing and the products ask of it. `check.res`
 * asks of every step of the bootstrap path that each deployment's footing, of the platform and of an
 * organization alike, holds one kind of each class, its compute an `effect` function; that its
 * extensions give every kind the products need; and that every resource reaches the public network
 * by a path, networks joined by jumps.
 */
type class = [#compute | #storage | #database]

/** A kind of what a resource gives; a database's sizes are open [C23]. */
type kind = [#function | #instance | #container | #object | #volume | #database]

let classOf = (k: kind): class =>
  switch k {
  | #function | #instance | #container => #compute
  | #object | #volume => #storage
  | #database => #database
  }

/**
 * A network a resource may be in, RFC vr5lw: the public one; Cloudflare's, joined by a tunnel; and a
 * relay's, joined by a connection held out to a machine with an address. A tailnet and a local
 * network are private networks as well, bound by an organization and on no ground here.
 */
type network = [#public | #cloudflare | #relay]

type resource = {
  gives: array<kind>,
  /** The networks it is in, where they stand: one in two is a jump between them. */
  in_: array<network>,
  /** The private networks it stands up, which it is a jump into from the public one. */
  stands?: array<network>,
  /** The CPU a call may take on each of the vendor's plans, in milliseconds, lessons.md. A machine's
   * driver declares how long a call may run as well, a value open [D8]; until it is, a machine is
   * taken here to bound nothing. */
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
  /* The internal platform's three products, given the external one through the driver's interface. */
  "internal products": {
    gives: [#function, #instance, #container, #object, #database],
    in_: [#public],
    from: "vr5lw, 94y0d",
  },
}

/** The resources each ground of `bootstrap.res` holds. */
let groundOf = (g: Bootstrap.ground) =>
  switch g {
  | #cloudflare => ["worker", "durable object", "d1", "r2"]
  | #provider => ["machine"]
  | #home => ["machine at home"]
  | #internal => ["internal products"]
  }

/** What cutting and sealing a parcel takes of CPU in a call, in milliseconds: assumed, an order
 * past a free Worker's 10, until it is measured. */
let assumedSealCpu = 100.

type need = {any: array<kind>, cpu?: float, why: string}

/**
 * What the products ask of an organization's extensions in v0, each met by any of its kinds: a
 * function for compute; a database for the database product, given in the platform's contract or
 * as a tablet whose one writer an instance holds, RFC 49qyg; and objects for the storage and a
 * tablet's archive, RFC vuanj. The rest of a kind is asked only by an app that declares it.
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

let resourcesOf = (d: Bootstrap.deployment) =>
  d.ground->Array.flatMap(groundOf)->Array.map(n => (n, get(resources, n)))

/** What of a deployment's resources reaches the public network by no path, vr5lw: a private
 * network stands only where something of the deployment stands it up, and a resource in two that
 * stand joins them. */
let unreached = (d: Bootstrap.deployment): array<string> => {
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

let usable = (r: resource, d: Bootstrap.deployment) =>
  !(r.metered->Option.getOr(false)) || d.on->Array.includes(#metering)

/** What a deployment's footing may hold: anything its ground gives, the paid plan aside, since a
 * footing's compute runs the control's own code and never an app's. */
let footingKinds = (d: Bootstrap.deployment): Set.t<kind> =>
  Set.fromArray(
    d.ground
    ->Array.flatMap(groundOf)
    ->Array.map(n => get(resources, n))
    ->Array.filter(r => usable(r, d))
    ->Array.flatMap(r => r.gives),
  )

/** What a deployment's extensions may give, compute, storage and databases, each kind with the
 * most CPU a call may take of it on the deployment's plan. */
let extensionKinds = (d: Bootstrap.deployment): Map.t<kind, float> => {
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
