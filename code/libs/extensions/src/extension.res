/***
 * A control's extensions, RFCs v7v3w, vr5lw and kd7f9, each record made or judged of what the
 * caller hands it.
 */
open Envelope

type declared = {
  host: Contracts.ExtensionHost.t,
  levels: Contracts.Placement.t,
  place: Contracts.ExtensionPlace.t,
  address: bool,
}

type binding = {
  endpoint: string,
  token: Uint8Array.t,
  relays: Contracts.ExtensionRelays.t,
  levels?: Contracts.Placement.t,
  place?: Contracts.ExtensionPlace.t,
  quota?: float,
  grace?: float,
  management?: Uint8Array.t,
  shell?: Uint8Array.t,
}

type unbound =
  | Grace(float)
  | Relays

let year = 31536000.
let week = 604800.

/** Whether relays name all, or one or more each once. */
let relaysHeld = (relays: Contracts.ExtensionRelays.t) =>
  switch relays {
  | All => true
  | Some({extensions}) =>
    extensions != [] &&
      extensions->Array.everyWithIndex((e, at) => extensions->Array.indexOf(e) == at)
  }

let bind = (declared, binding) => {
  let refused = []
  switch binding.grace {
  | Some(grace) if grace > year => refused->Array.push(Grace(grace))
  | Some(_) | None => ()
  }
  if !relaysHeld(binding.relays) {
    refused->Array.push(Relays)
  }
  switch refused {
  | [] =>
    Ok(
      (
        {
          host: declared.host,
          endpoint: binding.endpoint,
          token: binding.token,
          levels: binding.levels->Option.getOr(declared.levels),
          place: binding.place->Option.getOr(declared.place),
          quota: ?binding.quota,
          grace: ?binding.grace,
          relays: binding.relays,
          address: declared.address,
          management: ?binding.management,
          shell: ?binding.shell,
          dismissed: [],
        }: Contracts.Extension.t
      ),
    )
  | _ => Error(refused)
  }
}

let grace = (extension: Contracts.Extension.t, ~organization: Contracts.Organization.t) =>
  switch (extension.grace, organization.grace) {
  | (Some(own), _) => own
  | (None, Some(inherited)) => inherited
  | (None, None) => week
  }

let quota = (extension: Contracts.Extension.t, ~organization: Contracts.Organization.t) =>
  switch extension.quota {
  | Some(own) => Some(own)
  | None => organization.quota
  }

type set =
  | Pool
  | Keyed
  | Copies

type member = {levels: Contracts.Placement.t, place: Contracts.ExtensionPlace.t}

/** A level's code, RFC 13ixj, compared as an integer. */
let availability = (level: Contracts.Availability.t) =>
  switch level {
  | Opportunistic => 1
  | BestEffort => 2
  | Stable => 3
  | Recoverable => 4
  | Redundant => 5
  | Multiregion => 6
  }

let durability = (level: Contracts.Durability.t) =>
  switch level {
  | Ephemeral => 1
  | Persistent => 2
  | Redundant => 3
  | Replicated => 4
  | Multizone => 5
  | Multiregion => 6
  }

let custody = (level: Contracts.Custody.t) =>
  switch level {
  | False => 0
  | True => 1
  }

let lower = (code, a, b) => code(b) < code(a) ? b : a
let higher = (code, a, b) => code(b) > code(a) ? b : a

/** A domain two members may lie apart in, each within the next wider. */
type domain = [#node | #site | #zone | #region]

let valueIn = (place: Contracts.ExtensionPlace.t, domain: domain) =>
  switch domain {
  | #node => place.node
  | #site => place.site
  | #zone => place.zone
  | #region => place.region
  }

/** The domains a domain lies within, a node in a site, a site in a zone, a zone in a region. */
let within = (domain: domain): array<domain> =>
  switch domain {
  | #node => [#node, #site, #zone, #region]
  | #site => [#site, #zone, #region]
  | #zone => [#zone, #region]
  | #region => [#region]
  }

/** Whether two places are apart in a domain, by it or a wider one both name apart, RFC 87lwb. */
let apart = (a, b, domain) =>
  within(domain)->Array.some(d =>
    switch (valueIn(a, d), valueIn(b, d)) {
    | (Some(x), Some(y)) => x != y
    | (Some(_), None) | (None, Some(_)) | (None, None) => false
    }
  )

/** Whether two members or more lie apart in a domain. */
let spread = (members: array<member>, domain) =>
  members->Array.some(a => members->Array.some(b => apart(a.place, b.place, domain)))

let compose = (set, members: array<member>) =>
  members
  ->Array.get(0)
  ->Option.map(first => {
    let own = members->Array.reduce(first.levels, (low, m): Contracts.Placement.t => {
      availability: lower(availability, low.availability, m.levels.availability),
      durability: lower(durability, low.durability, m.levels.durability),
      custody: lower(custody, low.custody, m.levels.custody),
    })
    let composing = members->Array.filter(m => availability(m.levels.availability) >= 3)
    let composed: (option<Contracts.Availability.t>, option<Contracts.Durability.t>) = switch set {
    | Pool if spread(composing, #region) => (Some(Multiregion), None)
    | Pool if spread(composing, #node) => (Some(Redundant), None)
    | Keyed if spread(composing, #node) => (Some(Recoverable), None)
    | Pool | Keyed => (None, None)
    | Copies =>
      let kept = composing->Array.filter(m => durability(m.levels.durability) >= 2)
      if spread(kept, #region) {
        (None, Some(Multiregion))
      } else if spread(kept, #zone) {
        (None, Some(Multizone))
      } else if spread(kept, #node) {
        (None, Some(Replicated))
      } else {
        (None, None)
      }
    }
    let (a, d) = composed

    (
      {
        availability: a->Option.mapOr(own.availability, higher(availability, own.availability, _)),
        durability: d->Option.mapOr(own.durability, higher(durability, own.durability, _)),
        custody: own.custody,
      }: Contracts.Placement.t
    )
  })

type listed = {id: float, capacity: Contracts.Capacity.t, hashes: array<Uint8Array.t>}

type unlisted =
  | Repeated(float)
  | Credentials(float)
  | Hash(float)
  | Token(int)

let hashed = hash => TypedArray.length(hash) == 32

let apply = (listed, ~extension, ~generation, ~tokens=?) => {
  let own =
    listed
    ->Array.filter(l => l.capacity.extension == extension)
    ->Array.toSorted((a, b) => Float.compare(a.id, b.id))
  let refused = []
  let seen = []
  let repeated = []
  own->Array.forEach(l => {
    if seen->Array.includes(l.id) && !(repeated->Array.includes(l.id)) {
      repeated->Array.push(l.id)
      refused->Array.push(Repeated(l.id))
    }
    seen->Array.push(l.id)
    let count = l.hashes->Array.length
    if count != l.capacity.credentials->Array.length || count < 1 || count > 2 {
      refused->Array.push(Credentials(l.id))
    }
    if !(l.hashes->Array.every(hashed)) {
      refused->Array.push(Hash(l.id))
    }
  })
  tokens
  ->Option.getOr([])
  ->Array.forEachWithIndex((token, at) =>
    if !hashed(token) {
      refused->Array.push(Token(at))
    }
  )
  switch refused {
  | [] =>
    Ok(
      (
        {
          generation,
          items: own->Array.map((l): Contracts.ManagementItem.t => {
            id: l.id,
            capacity: l.capacity.capacity,
            credentials: l.hashes,
          }),
          ?tokens,
        }: Contracts.ManagementApply.t
      ),
    )
  | _ => Error(refused)
  }
}

let lend = (extension: Contracts.Extension.t, ~quota): Contracts.AuthorityLoan.t => {
  host: extension.host,
  endpoint: extension.endpoint,
  levels: extension.levels,
  place: extension.place,
  quota,
  address: extension.address,
}

let borrow = (loan: Contracts.AuthorityLoan.t, ~lender, ~token, ~relays) =>
  bind(
    {host: loan.host, levels: loan.levels, place: loan.place, address: loan.address},
    {endpoint: loan.endpoint, token, relays, quota: loan.quota},
  )->Result.map(extension => {...extension, lender})
