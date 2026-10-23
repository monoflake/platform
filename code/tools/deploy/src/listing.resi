/***
 * The binding's list with a container for the app, what the machine already holds kept, RFC vr5lw
 * and RFC n0o4l.
 */
module Contracts = Envelope.Contracts

/** What the app's container is asked for, as hello's first list asked. */
let capacity: Contracts.ManagementCapacity.t

/** What is sent to the binding for the app's container, or none when the list already holds one. */
type planned =
  | Held({into: float})
  | Apply({list: Contracts.ManagementApply.t, into: float})

/**
 * The list with a container added at the next generation if none is asked, its credential the one
 * given; one asking other items is refused, as describe gives no credentials to keep them by.
 */
let planned: (Contracts.ManagementDescribed.t, ~credential: Uint8Array.t) => result<planned, string>

/** How far an item has been made. */
type made = Making | Made | Failed(string)

/** The state of the item of an id in what the binding holds, failed where none holds it. */
let madeOf: (Contracts.ManagementDescribed.t, float) => made
