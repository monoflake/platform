/***
 * `Listing` held to RFC vr5lw, a container added at the next generation only where none is asked,
 * and a list it cannot keep refused.
 */
open Node

module Contracts = Envelope.Contracts

// A maker of credentials, each filled with the next count, so no two are equal.
let counting = () => {
  let count = ref(0)
  () => {
    count := count.contents + 1
    Uint8Array.fromArray(Array.make(~length=32, count.contents))
  }
}

let credentialOf = n => Uint8Array.fromArray(Array.make(~length=32, n))

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
    Listing.planned(described(4., []), ~fresh=counting()),
    Ok(
      Apply({
        list: {
          generation: 5.,
          items: [{id: 1., capacity: Listing.capacity, credentials: [credentialOf(1)]}],
        },
        into: 1.,
        database: None,
      }),
    ),
  )
)

test("a container already asked is held, and nothing is sent", () => {
  deepEqual(
    Listing.planned(
      described(1., [holding(3., Listing.capacity, Made({address: "a"}))]),
      ~fresh=counting(),
    ),
    Ok(Held({into: 3., database: None})),
  )
  deepEqual(
    Listing.planned(described(1., [holding(2., Listing.capacity, Making)]), ~fresh=counting()),
    Ok(Held({into: 2., database: None})),
  )
})

test("an unasked item is no container, and its id is taken by none", () =>
  switch Listing.planned(
    described(2., [holding(7., Listing.capacity, Unasked({since: 1.}))]),
    ~fresh=counting(),
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
      ~fresh=counting(),
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

let databased: Contracts.ManagementCapacity.t = Database({size: 1024.})
let newDatabase: Contracts.ManagementCapacity.t = Database({size: 268435456.})

test("a database slot adds a database of 268435456 bytes beside the container", () =>
  deepEqual(
    Listing.planned(described(4., []), ~fresh=counting(), ~slot=true),
    Ok(
      Apply({
        list: {
          generation: 5.,
          items: [
            {id: 1., capacity: Listing.capacity, credentials: [credentialOf(1)]},
            {id: 2., capacity: newDatabase, credentials: [credentialOf(2)]},
          ],
        },
        into: 1.,
        database: Some(2.),
      }),
    ),
  )
)

test("a Made database fills the slot, the lowest id among the Made, and nothing is sent", () => {
  deepEqual(
    Listing.planned(
      described(
        1.,
        [
          holding(1., Listing.capacity, Made({address: "a"})),
          holding(5., databased, Made({address: "d"})),
          holding(3., databased, Made({address: "e"})),
          holding(2., databased, Making),
        ],
      ),
      ~fresh=counting(),
      ~slot=true,
    ),
    Ok(Held({into: 1., database: Some(3.)})),
  )
  deepEqual(
    Listing.planned(
      described(1., [holding(1., Listing.capacity, Making), holding(2., databased, Making)]),
      ~fresh=counting(),
    ),
    Ok(Held({into: 1., database: None})),
  )
})

test("a Made database beside a Failed one with a lower id fills the slot", () =>
  deepEqual(
    Listing.planned(
      described(
        1.,
        [
          holding(1., Listing.capacity, Made({address: "a"})),
          holding(3., databased, Failed({reason: "beyond_host"})),
          holding(5., databased, Made({address: "d"})),
        ],
      ),
      ~fresh=counting(),
      ~slot=true,
    ),
    Ok(Held({into: 1., database: Some(5.)})),
  )
)

test("a database unasked is no database, and its id is taken by none", () =>
  switch Listing.planned(
    described(2., [holding(7., databased, Unasked({since: 1.}))]),
    ~fresh=counting(),
    ~slot=true,
  ) {
  | Ok(Apply({list, into, database})) =>
    deepEqual((into, database), (8., Some(9.)))
    deepEqual(list.items->Array.map(i => i.id), [8., 9.])
  | Ok(Held(_)) | Error(_) => ok(false, ~message="no list planned")
  }
)

test("a container held and no database sends both again, and a database alone is refused", () => {
  switch Listing.planned(
    described(1., [holding(1., Listing.capacity, Made({address: "a"}))]),
    ~fresh=counting(),
    ~slot=true,
  ) {
  | Ok(Apply({list, into, database: Some(filled)})) =>
    deepEqual((into, filled, list.generation), (1., 2., 2.))
    deepEqual(list.items->Array.map(i => i.id), [1., 2.])
  | Ok(Apply({database: None})) | Ok(Held(_)) | Error(_) => ok(false, ~message="no list planned")
  }
  ok(
    Listing.planned(
      described(1., [holding(2., databased, Made({address: "d"}))]),
      ~fresh=counting(),
      ~slot=true,
    )->Result.isError,
  )
})

test("Failed or Making databases and no Made one send the list again with a new database", () =>
  [Contracts.ManagementState.Making, Failed({reason: "beyond_host"})]->Array.forEach(state =>
    switch Listing.planned(
      described(
        3.,
        [
          holding(1., Listing.capacity, Made({address: "a"})),
          holding(2., volume, Made({address: "v"})),
          holding(4., databased, state),
          holding(9., databased, Unasked({since: 1.})),
        ],
      ),
      ~fresh=counting(),
      ~slot=true,
    ) {
    | Ok(Apply({list, into, database})) =>
      deepEqual((into, database, list.generation), (1., Some(10.), 4.))
      deepEqual(
        list.items->Array.map(i => (i.id, i.capacity)),
        [(1., Listing.capacity), (2., volume), (10., newDatabase)],
      )
    | Ok(Held(_)) | Error(_) => ok(false, ~message="no list planned")
    }
  )
)

test("every item sent again carries a credential no other carries", () =>
  switch Listing.planned(
    described(
      3.,
      [
        holding(1., Listing.capacity, Made({address: "a"})),
        holding(2., volume, Made({address: "v"})),
        holding(4., databased, Failed({reason: "beyond_host"})),
      ],
    ),
    ~fresh=counting(),
    ~slot=true,
  ) {
  | Ok(Apply({list})) =>
    let credentials =
      list.items->Array.flatMap(i =>
        i.credentials->Array.map(c => c->TypedArray.get(0)->Option.getOr(-1))
      )
    deepEqual(credentials->Array.length, 3)
    deepEqual(Set.fromArray(credentials)->Set.size, 3)
  | Ok(Held(_)) | Error(_) => ok(false, ~message="no list planned")
  }
)

test("a container and a database made together carry credentials of their own", () =>
  switch Listing.planned(described(1., []), ~fresh=counting(), ~slot=true) {
  | Ok(Apply({list})) =>
    let credentials =
      list.items->Array.flatMap(i =>
        i.credentials->Array.map(c => c->TypedArray.get(0)->Option.getOr(-1))
      )
    deepEqual(Set.fromArray(credentials)->Set.size, 2)
  | Ok(Held(_)) | Error(_) => ok(false, ~message="no list planned")
  }
)
