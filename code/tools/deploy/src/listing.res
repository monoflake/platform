module Contracts = Envelope.Contracts

let capacity: Contracts.ManagementCapacity.t = Container({millicores: 500., memory: 268435456.})

let databaseCapacity: Contracts.ManagementCapacity.t = Database({size: 268435456.})

type planned =
  | Held({into: float, database: option<float>})
  | Apply({list: Contracts.ManagementApply.t, into: float, database: option<float>})

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

/** The Made database item with the lowest id, so the same one fills a slot on every deploy. */
let firstMadeDatabase = (asked: array<Contracts.ManagementHolding.t>) =>
  asked
  ->Array.filter(i => isDatabase(i.capacity) && isMade(i.state))
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
let planned = (described: Contracts.ManagementDescribed.t, ~fresh, ~slot=false) => {
  let asked = described.items->Array.filter(i => isAsked(i.state))
  let item = (id, capacity): Contracts.ManagementItem.t => {id, capacity, credentials: [fresh()]}
  switch (asked->Array.find(i => isContainer(i.capacity)), firstMadeDatabase(asked), slot, asked) {
  | (Some(held), _, false, _) => Ok(Held({into: held.id, database: None}))
  | (Some(held), Some(database), true, _) => Ok(Held({into: held.id, database: Some(database.id)}))
  | (Some(held), None, true, asked) =>
    // What it asks is sent again under new credentials, which a machine holds and reads not.
    let id = nextId(described)
    let kept =
      asked->Array.filter(i => !isDatabase(i.capacity))->Array.map(i => item(i.id, i.capacity))
    let items = [...kept, item(id, databaseCapacity)]
    Ok(
      Apply({
        list: {generation: described.generation +. 1., items},
        into: held.id,
        database: Some(id),
      }),
    )
  | (None, _, _, []) =>
    let into = nextId(described)
    let items = [item(into, capacity)]
    let (items, database) = slot
      ? ([...items, item(into +. 1., databaseCapacity)], Some(into +. 1.))
      : (items, None)
    Ok(Apply({list: {generation: described.generation +. 1., items}, into, database}))
  | (None, _, _, others) =>
    Error(
      `the binding asks ${others
        ->Array.map(i => Float.toString(i.id))
        ->Array.join(
          ", ",
        )} and no container, and describe gives no item's credentials to keep them`,
    )
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
