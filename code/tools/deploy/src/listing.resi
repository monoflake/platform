/***
 * The binding's list with a container for the app, what the machine already holds kept, RFC vr5lw
 * and RFC n0o4l.
 */
module Contracts = Envelope.Contracts

/** What the app's container is asked for, as hello's first list asked. */
let capacity: Contracts.ManagementCapacity.t

/** What a build's database slot is filled from, a database of this many bytes, RFC rt6gi. */
let databaseCapacity: Contracts.ManagementCapacity.t

/**
 * What is sent to the binding for the app's container, and its database where the build declares a
 * slot, or nothing when the list holds them. `database` is the id of the item filling the slots.
 */
type planned =
  | Held({into: float, database: option<float>})
  | Apply({list: Contracts.ManagementApply.t, into: float, database: option<float>})

/**
 * The list with a container added at the next generation if none is asked, its credential the one
 * given, and a database beside it, its credential `database`, where that is given and none is
 * asked, what it asks sent again under that credential; one asking other items and no container is
 * refused, as describe gives no credentials to keep them by.
 */
let planned: (
  Contracts.ManagementDescribed.t,
  ~credential: Uint8Array.t,
  ~database: Uint8Array.t=?,
) => result<planned, string>

/** How far an item has been made. */
type made = Making | Made | Failed(string)

/** The state of the item of an id in what the binding holds, failed where none holds it. */
let madeOf: (Contracts.ManagementDescribed.t, float) => made
