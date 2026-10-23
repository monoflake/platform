module Contracts = Envelope.Contracts

let capacity: Contracts.ManagementCapacity.t = Container({millicores: 500., memory: 268435456.})

type planned =
  | Held({into: float})
  | Apply({list: Contracts.ManagementApply.t, into: float})

let isContainer = (capacity: Contracts.ManagementCapacity.t) =>
  switch capacity {
  | Container(_) => true
  | Volume(_) | Object(_) | Database(_) => false
  }

let isAsked = (state: Contracts.ManagementState.t) =>
  switch state {
  | Making | Made(_) | Failed(_) => true
  | Unasked(_) => false
  }

let planned = (described: Contracts.ManagementDescribed.t, ~credential) => {
  let asked = described.items->Array.filter(i => isAsked(i.state))
  switch (asked->Array.find(i => isContainer(i.capacity)), asked) {
  | (Some(held), _) => Ok(Held({into: held.id}))
  | (None, []) =>
    // An id past every one the binding holds, an unasked one's too, so none is taken again.
    let into = described.items->Array.reduce(0., (most, i) => Math.max(most, i.id)) +. 1.
    Ok(
      Apply({
        list: {
          generation: described.generation +. 1.,
          items: [{id: into, capacity, credentials: [credential]}],
        },
        into,
      }),
    )
  | (None, others) =>
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
