module Contracts = Envelope.Contracts

let capacity: Contracts.ManagementCapacity.t = Container({millicores: 500., memory: 268435456.})

let databaseCapacity: Contracts.ManagementCapacity.t = Database({size: 268435456.})

let objectCapacity: Contracts.ManagementCapacity.t = Object({size: 268435456.})

type planned =
  | Held({into: float, database: option<float>, object: option<float>})
  | Apply({
      list: Contracts.ManagementApply.t,
      into: float,
      database: option<float>,
      object: option<float>,
    })

let isContainer = (capacity: Contracts.ManagementCapacity.t) =>
  switch capacity {
  | Container(_) => true
  | Volume(_) | Object(_) | Database(_) => false
  }

let isDatabase = (capacity: Contracts.ManagementCapacity.t) =>
  switch capacity {
  | Database(_) => true
  | Container(_) | Volume(_) | Object(_) => false
  }

let isObject = (capacity: Contracts.ManagementCapacity.t) =>
  switch capacity {
  | Object(_) => true
  | Container(_) | Volume(_) | Database(_) => false
  }

let isAsked = (state: Contracts.ManagementState.t) =>
  switch state {
  | Making | Made(_) | Failed(_) => true
  | Unasked(_) => false
  }

let isMade = (state: Contracts.ManagementState.t) =>
  switch state {
  | Made(_) => true
  | Making | Failed(_) | Unasked(_) => false
  }

/** The Made item of a kind with the lowest id, so the same one fills a slot on every deploy. */
let firstMade = (asked: array<Contracts.ManagementHolding.t>, ~kind) =>
  asked
  ->Array.filter(i => kind(i.capacity) && isMade(i.state))
  ->Array.reduce(None, (first: option<Contracts.ManagementHolding.t>, i) =>
    switch first {
    | Some(held) if held.id <= i.id => first
    | Some(_) | None => Some(i)
    }
  )

/** An id past every one the binding holds, an unasked one's too, so none is taken again. */
let nextId = (described: Contracts.ManagementDescribed.t) =>
  described.items->Array.reduce(0., (most, i) => Math.max(most, i.id)) +. 1.

/** `fresh` makes a new credential on every call, so no two items share one. */
let planned = (
  described: Contracts.ManagementDescribed.t,
  ~fresh,
  ~database=false,
  ~bucket=false,
) => {
  let asked = described.items->Array.filter(i => isAsked(i.state))
  let item = (id, capacity): Contracts.ManagementItem.t => {id, capacity, credentials: [fresh()]}
  // The ids of what is added, in order, from the first past every id held.
  let added = (first, ~needed) => {
    let at = ref(first)
    needed->Array.map(capacity => {
      let id = at.contents
      at := id +. 1.
      item(id, capacity)
    })
  }
  let idOf = (items: array<Contracts.ManagementItem.t>, ~kind) =>
    items->Array.find(i => kind(i.capacity))->Option.map(i => i.id)
  switch asked->Array.find(i => isContainer(i.capacity)) {
  | Some(held) =>
    let madeDatabase = database ? firstMade(asked, ~kind=isDatabase) : None
    let madeObject = bucket ? firstMade(asked, ~kind=isObject) : None
    let needed = Array.concat(
      database && Option.isNone(madeDatabase) ? [databaseCapacity] : [],
      bucket && Option.isNone(madeObject) ? [objectCapacity] : [],
    )
    switch needed {
    | [] =>
      Ok(
        Held({
          into: held.id,
          database: madeDatabase->Option.map(i => i.id),
          object: madeObject->Option.map(i => i.id),
        }),
      )
    | _ =>
      // What it asks is sent again under new credentials, which a machine holds and reads not.
      let dropped = capacity =>
        (database && Option.isNone(madeDatabase) && isDatabase(capacity)) ||
          (bucket && Option.isNone(madeObject) && isObject(capacity))
      let kept =
        asked->Array.filter(i => !dropped(i.capacity))->Array.map(i => item(i.id, i.capacity))
      let extra = added(nextId(described), ~needed)
      let items = [...kept, ...extra]
      Ok(
        Apply({
          list: {generation: described.generation +. 1., items},
          into: held.id,
          database: madeDatabase
          ->Option.map(i => i.id)
          ->Option.orElse(idOf(extra, ~kind=isDatabase)),
          object: madeObject->Option.map(i => i.id)->Option.orElse(idOf(extra, ~kind=isObject)),
        }),
      )
    }
  | None =>
    switch asked {
    | [] =>
      let into = nextId(described)
      let needed = Array.concat(database ? [databaseCapacity] : [], bucket ? [objectCapacity] : [])
      let container = item(into, capacity)
      let more = added(into +. 1., ~needed)
      Ok(
        Apply({
          list: {
            generation: described.generation +. 1.,
            items: [container, ...more],
          },
          into,
          database: idOf(more, ~kind=isDatabase),
          object: idOf(more, ~kind=isObject),
        }),
      )
    | others =>
      Error(
        `the binding asks ${others
          ->Array.map(i => Float.toString(i.id))
          ->Array.join(
            ", ",
          )} and no container, and describe gives no item's credentials to keep them`,
      )
    }
  }
}

type made = Making | Made | Failed(string)

let madeOf = (described: Contracts.ManagementDescribed.t, id) =>
  switch described.items->Array.find(i => i.id == id) {
  | None => Failed(`no item ${Float.toString(id)} is held`)
  | Some({state: Making}) => Making
  | Some({state: Made(_)}) => Made
  | Some({state: Failed({reason, ?message})}) =>
    Failed(message->Option.mapOr(reason, m => `${reason}, ${m}`))
  | Some({state: Unasked(_)}) => Failed(`item ${Float.toString(id)} is no longer asked`)
  }
