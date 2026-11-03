/***
 * The binding's list with a container for the app, what the machine already holds kept, RFC vr5lw
 * and RFC n0o4l.
 */
module Contracts = Envelope.Contracts

/** What the app's container is asked for, as hello's first list asked. */
let capacity: Contracts.ManagementCapacity.t

/** What a build's database slot is filled from, a database of this many bytes, RFC rt6gi. */
let databaseCapacity: Contracts.ManagementCapacity.t

/** What a build's object bucket slot is filled from, an object item of this many bytes. */
let objectCapacity: Contracts.ManagementCapacity.t

/** The component's low 31 bits with the high bit set, reserved for its records item. */
let computeId: float => float

/**
 * What is sent to the binding for the app's container, and its database and object item where the
 * build declares slots for them, or nothing when the list holds them. `database`, `records` and
 * `object` are the ids of the items filling the slots: the apps' database, compute's own records
 * item, and the object item.
 */
type planned =
  | Held({into: float, database: option<float>, records: option<float>, object: option<float>})
  | Apply({
      list: Contracts.ManagementApply.t,
      into: float,
      database: option<float>,
      records: option<float>,
      object: option<float>,
    })

/**
 * The list with a container added at the next generation if none is asked, and a database and an
 * object item beside it where `database` and `bucket` say the build declares slots for them, and
 * with `compute` its records item at `computeId`, kept in any asked state. A wanted kind with no
 * Made item is sent again without its asked items and with a new one. Every item sent takes a
 * credential from `fresh`, called once for each; other items and no container are refused.
 */
let planned: (
  Contracts.ManagementDescribed.t,
  ~fresh: unit => Uint8Array.t,
  ~database: bool=?,
  ~bucket: bool=?,
  ~compute: float=?,
) => result<planned, string>

/** How far an item has been made. */
type made = Making | Made | Failed(string)

/** The state of the item of an id in what the binding holds, failed where none holds it. */
let madeOf: (Contracts.ManagementDescribed.t, float) => made
