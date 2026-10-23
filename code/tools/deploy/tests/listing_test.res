/***
 * `Listing` held to RFC vr5lw, a container added at the next generation only where none is asked,
 * and a list it cannot keep refused.
 */
open Node

module Contracts = Envelope.Contracts

let credential = Uint8Array.fromLength(32)

let holding = (id, capacity, state): Contracts.ManagementHolding.t => {id, capacity, state}

let described = (generation, items): Contracts.ManagementDescribed.t => {
  generation,
  policy: 0.,
  grace: 0.,
  items,
}

let volume: Contracts.ManagementCapacity.t = Volume({size: 1024.})

test("an empty list is sent again with one container, at the next generation", () =>
  deepEqual(
    Listing.planned(described(4., []), ~credential),
    Ok(
      Apply({
        list: {
          generation: 5.,
          items: [{id: 1., capacity: Listing.capacity, credentials: [credential]}],
        },
        into: 1.,
      }),
    ),
  )
)

test("a container already asked is held, and nothing is sent", () => {
  deepEqual(
    Listing.planned(
      described(1., [holding(3., Listing.capacity, Made({address: "a"}))]),
      ~credential,
    ),
    Ok(Held({into: 3.})),
  )
  deepEqual(
    Listing.planned(described(1., [holding(2., Listing.capacity, Making)]), ~credential),
    Ok(Held({into: 2.})),
  )
})

test("an unasked item is no container, and its id is taken by none", () =>
  switch Listing.planned(
    described(2., [holding(7., Listing.capacity, Unasked({since: 1.}))]),
    ~credential,
  ) {
  | Ok(Apply({list, into})) =>
    deepEqual(into, 8.)
    deepEqual(list.generation, 3.)
    deepEqual(list.items->Array.map(i => i.id), [8.])
  | Ok(Held(_)) | Error(_) => ok(false, ~message="no list planned")
  }
)

test("a list asking anything but a container is refused, its credentials not described", () =>
  ok(
    Listing.planned(
      described(1., [holding(1., volume, Made({address: "v"}))]),
      ~credential,
    )->Result.isError,
  )
)

test("an item's state is read by its id", () => {
  let held = described(
    1.,
    [holding(1., Listing.capacity, Making), holding(2., volume, Made({address: "v"}))],
  )
  deepEqual(Listing.madeOf(held, 1.), Making)
  deepEqual(Listing.madeOf(held, 2.), Made)
  ok(
    switch Listing.madeOf(held, 3.) {
    | Failed(_) => true
    | Making | Made => false
    },
  )
  deepEqual(
    Listing.madeOf(
      described(
        1.,
        [holding(1., Listing.capacity, Failed({reason: "beyond_host", message: "full"}))],
      ),
      1.,
    ),
    Failed("beyond_host, full"),
  )
})
