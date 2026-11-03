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

/** The database item with the lowest id, so the same one fills a slot on every deploy. */
let firstDatabase = (asked: array<Contracts.ManagementHolding.t>) =>
  asked
  ->Array.filter(i => isDatabase(i.capacity))
  ->Array.reduce(None, (first: option<Contracts.ManagementHolding.t>, i) =>
    switch first {
    | Some(held) if held.id <= i.id => first
    | Some(_) | None => Some(i)
    }
  )

let planned = (described: Contracts.ManagementDescribed.t, ~credential, ~database=?) => {
  let asked = described.items->Array.filter(i => isAsked(i.state))
  switch (asked->Array.find(i => isContainer(i.capacity)), firstDatabase(asked), database, asked) {
  | (Some(held), _, None, _) => Ok(Held({into: held.id, database: None}))
  | (Some(held), Some(db), Some(_), _) => Ok(Held({into: held.id, database: Some(db.id)}))
  | (Some(held), None, Some(credential), asked) =>
    // What it asks is sent again under a new credential, which a machine holds and reads not.
    let id = described.items->Array.reduce(0., (most, i) => Math.max(most, i.id)) +. 1.
    let kept: array<Contracts.ManagementItem.t> = asked->Array.map((
      i
    ): Contracts.ManagementItem.t => {
      id: i.id,
      capacity: i.capacity,
      credentials: [credential],
    })
    let items = [...kept, {id, capacity: databaseCapacity, credentials: [credential]}]
    Ok(
      Apply({
        list: {generation: described.generation +. 1., items},
        into: held.id,
        database: Some(id),
      }),
    )
  | (None, _, _, []) =>
    // An id past every one the binding holds, an unasked one's too, so none is taken again.
    let into = described.items->Array.reduce(0., (most, i) => Math.max(most, i.id)) +. 1.
    let items: array<Contracts.ManagementItem.t> = [{id: into, capacity, credentials: [credential]}]
    let (items, database) = switch database {
    | None => (items, None)
    | Some(credential) => (
        [...items, {id: into +. 1., capacity: databaseCapacity, credentials: [credential]}],
        Some(into +. 1.),
      )
    }
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
