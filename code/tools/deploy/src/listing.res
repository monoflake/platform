module Contracts = Envelope.Contracts

let capacity: Contracts.ManagementCapacity.t = Container({millicores: 500., memory: 268435456.})

let databaseCapacity: Contracts.ManagementCapacity.t = Database({size: 268435456.})

let objectCapacity: Contracts.ManagementCapacity.t = Object({size: 268435456.})

let computeId = component =>
  2147483648. +. component -. Math.floor(component /. 2147483648.) *. 2147483648.

let isComputeId = id => id >= 2147483648. && id <= 4294967295.

type planned =
  | Held({into: float, database: option<float>, records: option<float>, object: option<float>})
  | Apply({
      list: Contracts.ManagementApply.t,
      into: float,
      database: option<float>,
      records: option<float>,
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
  described.items
  ->Array.filter(i => !isComputeId(i.id))
  ->Array.reduce(0., (most, i) => Math.max(most, i.id)) +. 1.

/** `fresh` makes a new credential on every call, so no two items share one. */
let planned = (
  described: Contracts.ManagementDescribed.t,
  ~fresh,
  ~database=false,
  ~bucket=false,
  ~compute=?,
) => {
  let asked = described.items->Array.filter(i => isAsked(i.state))
  let ordinary = asked->Array.filter(i => !isComputeId(i.id))
  let records = compute->Option.map(computeId)
  let collision =
    records->Option.flatMap(id =>
      described.items->Array.find(i => i.id == id && !isDatabase(i.capacity))
    )
  let recordsHeld = database
    ? records->Option.flatMap(id => asked->Array.find(i => i.id == id))
    : None
  let madeDatabase = database ? firstMade(ordinary, ~kind=isDatabase) : None
  let madeObject = bucket ? firstMade(asked, ~kind=isObject) : None
  let item = (id, capacity): Contracts.ManagementItem.t => {id, capacity, credentials: [fresh()]}
  // What is added, the apps' database then compute's records then the object item, in list order.
  let added = first => {
    let at = ref(first)
    let next = capacity => {
      let id = at.contents
      at := id +. 1.
      item(id, capacity)
    }
    let apps = database && Option.isNone(madeDatabase) ? [next(databaseCapacity)] : []
    let own =
      database && Option.isNone(recordsHeld)
        ? records->Option.mapOr([], id => [item(id, databaseCapacity)])
        : []
    let object = bucket && Option.isNone(madeObject) ? [next(objectCapacity)] : []
    (
      [...apps, ...own, ...object],
      madeDatabase->Option.map(i => i.id)->Option.orElse(apps[0]->Option.map(i => i.id)),
      recordsHeld->Option.map(i => i.id)->Option.orElse(own[0]->Option.map(i => i.id)),
      madeObject->Option.map(i => i.id)->Option.orElse(object[0]->Option.map(i => i.id)),
    )
  }
  let ownHeld = Option.isNone(records) || Option.isSome(recordsHeld)
  let complete =
    (!database || (Option.isSome(madeDatabase) && ownHeld)) &&
      (!bucket || Option.isSome(madeObject))
  switch (collision, asked->Array.find(i => isContainer(i.capacity))) {
  | (Some(i), _) =>
    Error(`compute records id ${Float.toString(i.id)} is held by a non-database item`)
  | (None, _) if nextId(described) +. 2. >= 2147483648. =>
    Error("the binding has no ordinary capacity ids left")
  | (None, Some(held)) if complete =>
    Ok(
      Held({
        into: held.id,
        database: madeDatabase->Option.map(i => i.id),
        records: recordsHeld->Option.map(i => i.id),
        object: madeObject->Option.map(i => i.id),
      }),
    )
  | (None, Some(held)) =>
    // What it asks is sent again under new credentials, which a machine holds and reads not.
    let dropped = (i: Contracts.ManagementHolding.t) =>
      (database && Option.isNone(madeDatabase) && isDatabase(i.capacity) && !isComputeId(i.id)) ||
        (bucket && Option.isNone(madeObject) && isObject(i.capacity))
    let kept = asked->Array.filter(i => !dropped(i))->Array.map(i => item(i.id, i.capacity))
    let (extra, database, records, object) = added(nextId(described))
    Ok(
      Apply({
        list: {generation: described.generation +. 1., items: [...kept, ...extra]},
        into: held.id,
        database,
        records,
        object,
      }),
    )
  | (None, None) =>
    switch ordinary {
    | [] =>
      let into = nextId(described)
      let kept = asked->Array.map(i => item(i.id, i.capacity))
      let container = item(into, capacity)
      let (more, database, records, object) = added(into +. 1.)
      Ok(
        Apply({
          list: {
            generation: described.generation +. 1.,
            items: [...kept, container, ...more],
          },
          into,
          database,
          records,
          object,
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
