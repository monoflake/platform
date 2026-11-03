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

let applied = planned =>
  switch planned {
  | Ok(Listing.Apply({list, database})) => (list, database)
  | Ok(Held(_)) | Error(_) => JsExn.throw("no list planned")
  }

let completed = (list: Contracts.ManagementApply.t) =>
  described(
    list.generation,
    list.items->Array.map(i => holding(i.id, i.capacity, Made({address: "made"}))),
  )

// The list, the apps' database and compute's records item a planned Apply names.
let computed = planned =>
  switch planned {
  | Ok(Listing.Apply({list, database, records})) => (list, database, records)
  | Ok(Held(_)) | Error(_) => JsExn.throw("no list planned")
  }

test(
  "compute first lists the apps' database and its own records, and an app reuses the first",
  () => {
    let compute = 305419896.
    let records = Listing.computeId(compute)
    let (first, database, own) =
      Listing.planned(described(0., []), ~fresh=counting(), ~database=true, ~compute)->computed
    deepEqual((database, own), (Some(2.), Some(records)))
    deepEqual(first.items->Array.map(i => i.id), [1., 2., records])
    deepEqual(
      Listing.planned(completed(first), ~fresh=counting(), ~database=true),
      Ok(Held({into: 1., database: Some(2.), records: None, object: None})),
    )
    deepEqual(
      Listing.planned(completed(first), ~fresh=counting(), ~database=true, ~compute),
      Ok(Held({into: 1., database: Some(2.), records: Some(records), object: None})),
    )
  },
)

test("an app first keeps its database when compute lists its derived records item", () => {
  let compute = 4294967295.
  let records = Listing.computeId(compute)
  let (first, _) = Listing.planned(described(0., []), ~fresh=counting(), ~database=true)->applied
  let (second, database, own) =
    Listing.planned(completed(first), ~fresh=counting(), ~database=true, ~compute)->computed
  deepEqual((database, own), (Some(2.), Some(records)))
  deepEqual(second.items->Array.map(i => i.id), [1., 2., records])
  deepEqual(
    Listing.planned(completed(second), ~fresh=counting(), ~database=true, ~compute),
    Ok(Held({into: 1., database: Some(2.), records: Some(records), object: None})),
  )
  deepEqual(
    Listing.planned(completed(second), ~fresh=counting(), ~database=true),
    Ok(Held({into: 1., database: Some(2.), records: None, object: None})),
  )
  deepEqual(
    Contracts.ManagementApply.fromJson(Contracts.ManagementApply.toJson(second)),
    Ok(second),
  )
})

test("compute's database is the apps' item an app deploy gets, the lowest Made id", () => {
  let compute = 9.
  let records = Listing.computeId(compute)
  let held = described(
    1.,
    [
      holding(1., Listing.capacity, Made({address: "a"})),
      holding(5., Listing.databaseCapacity, Made({address: "d"})),
      holding(3., Listing.databaseCapacity, Made({address: "e"})),
      holding(records, Listing.databaseCapacity, Made({address: "r"})),
    ],
  )
  deepEqual(
    Listing.planned(held, ~fresh=counting(), ~database=true),
    Ok(Held({into: 1., database: Some(3.), records: None, object: None})),
  )
  deepEqual(
    Listing.planned(held, ~fresh=counting(), ~database=true, ~compute),
    Ok(Held({into: 1., database: Some(3.), records: Some(records), object: None})),
  )
})

test("ordinary ids ignore compute items and refuse exhaustion before entering their range", () => {
  let records = Listing.computeId(1.)
  let (list, database) =
    Listing.planned(
      described(0., [holding(records, Listing.databaseCapacity, Made({address: "records"}))]),
      ~fresh=counting(),
      ~database=true,
      ~bucket=true,
    )->applied
  deepEqual(database, Some(2.))
  deepEqual(list.items->Array.map(i => i.id), [records, 1., 2., 3.])
  ok(
    Listing.planned(
      described(0., [holding(2147483647., Listing.capacity, Making)]),
      ~fresh=counting(),
      ~database=true,
    )->Result.isError,
  )
})

test("a non-database at compute's derived id is refused with its cause", () => {
  let compute = 1.
  let records = Listing.computeId(compute)
  deepEqual(
    Listing.planned(
      described(0., [holding(records, volume, Unasked({since: 0.}))]),
      ~fresh=counting(),
      ~database=true,
      ~compute,
    ),
    Error(`compute records id ${Float.toString(records)} is held by a non-database item`),
  )
})

test("compute reuses an existing records item while it is making or failed", () => {
  let compute = 1.
  let records = Listing.computeId(compute)
  [Contracts.ManagementState.Making, Failed({reason: "beyond_host"})]->Array.forEach(state => {
    let held = [
      holding(1., Listing.capacity, Making),
      holding(records, Listing.databaseCapacity, state),
    ]
    let (list, database, own) =
      Listing.planned(described(0., held), ~fresh=counting(), ~database=true, ~compute)->computed
    deepEqual((database, own), (Some(2.), Some(records)))
    deepEqual(list.items->Array.map(i => i.id), [1., records, 2.])
    deepEqual(
      Listing.planned(
        described(0., [...held, holding(2., Listing.databaseCapacity, Made({address: "d"}))]),
        ~fresh=counting(),
        ~database=true,
        ~compute,
      ),
      Ok(Held({into: 1., database: Some(2.), records: Some(records), object: None})),
    )
  })
})

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
        records: None,
        object: None,
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
    Ok(Held({into: 3., database: None, records: None, object: None})),
  )
  deepEqual(
    Listing.planned(described(1., [holding(2., Listing.capacity, Making)]), ~fresh=counting()),
    Ok(Held({into: 2., database: None, records: None, object: None})),
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
    Listing.planned(described(4., []), ~fresh=counting(), ~database=true),
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
        records: None,
        object: None,
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
      ~database=true,
    ),
    Ok(Held({into: 1., database: Some(3.), records: None, object: None})),
  )
  deepEqual(
    Listing.planned(
      described(1., [holding(1., Listing.capacity, Making), holding(2., databased, Making)]),
      ~fresh=counting(),
    ),
    Ok(Held({into: 1., database: None, records: None, object: None})),
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
      ~database=true,
    ),
    Ok(Held({into: 1., database: Some(5.), records: None, object: None})),
  )
)

test("a database unasked is no database, and its id is taken by none", () =>
  switch Listing.planned(
    described(2., [holding(7., databased, Unasked({since: 1.}))]),
    ~fresh=counting(),
    ~database=true,
  ) {
  | Ok(Apply({list, into, database, object: _})) =>
    deepEqual((into, database), (8., Some(9.)))
    deepEqual(list.items->Array.map(i => i.id), [8., 9.])
  | Ok(Held(_)) | Error(_) => ok(false, ~message="no list planned")
  }
)

test("a container held and no database sends both again, and a database alone is refused", () => {
  switch Listing.planned(
    described(1., [holding(1., Listing.capacity, Made({address: "a"}))]),
    ~fresh=counting(),
    ~database=true,
  ) {
  | Ok(Apply({list, into, database: Some(filled), object: _})) =>
    deepEqual((into, filled, list.generation), (1., 2., 2.))
    deepEqual(list.items->Array.map(i => i.id), [1., 2.])
  | Ok(Apply({database: None, _})) | Ok(Held(_)) | Error(_) => ok(false, ~message="no list planned")
  }
  ok(
    Listing.planned(
      described(1., [holding(2., databased, Made({address: "d"}))]),
      ~fresh=counting(),
      ~database=true,
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
      ~database=true,
    ) {
    | Ok(Apply({list, into, database, object: _})) =>
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
    ~database=true,
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
  switch Listing.planned(described(1., []), ~fresh=counting(), ~database=true) {
  | Ok(Apply({list})) =>
    let credentials =
      list.items->Array.flatMap(i =>
        i.credentials->Array.map(c => c->TypedArray.get(0)->Option.getOr(-1))
      )
    deepEqual(Set.fromArray(credentials)->Set.size, 2)
  | Ok(Held(_)) | Error(_) => ok(false, ~message="no list planned")
  }
)

let objectItem: Contracts.ManagementCapacity.t = Object({size: 1024.})
let newObject: Contracts.ManagementCapacity.t = Object({size: 268435456.})

test("an object bucket slot adds an object item of 268435456 bytes beside the container", () =>
  deepEqual(
    Listing.planned(described(4., []), ~fresh=counting(), ~bucket=true),
    Ok(
      Apply({
        list: {
          generation: 5.,
          items: [
            {id: 1., capacity: Listing.capacity, credentials: [credentialOf(1)]},
            {id: 2., capacity: newObject, credentials: [credentialOf(2)]},
          ],
        },
        into: 1.,
        database: None,
        records: None,
        object: Some(2.),
      }),
    ),
  )
)

test("a build declaring a database and an object bucket gets both items", () =>
  deepEqual(
    Listing.planned(described(0., []), ~fresh=counting(), ~database=true, ~bucket=true),
    Ok(
      Apply({
        list: {
          generation: 1.,
          items: [
            {id: 1., capacity: Listing.capacity, credentials: [credentialOf(1)]},
            {id: 2., capacity: newDatabase, credentials: [credentialOf(2)]},
            {id: 3., capacity: newObject, credentials: [credentialOf(3)]},
          ],
        },
        into: 1.,
        database: Some(2.),
        records: None,
        object: Some(3.),
      }),
    ),
  )
)

test("a Made object item fills the slot, the lowest id among the Made, and nothing is sent", () =>
  deepEqual(
    Listing.planned(
      described(
        1.,
        [
          holding(1., Listing.capacity, Made({address: "a"})),
          holding(5., objectItem, Made({address: "o"})),
          holding(3., objectItem, Made({address: "p"})),
          holding(2., objectItem, Making),
        ],
      ),
      ~fresh=counting(),
      ~bucket=true,
    ),
    Ok(Held({into: 1., database: None, records: None, object: Some(3.)})),
  )
)

test("a container held and no object item sends the list again with a new one", () =>
  switch Listing.planned(
    described(
      3.,
      [
        holding(1., Listing.capacity, Made({address: "a"})),
        holding(2., databased, Made({address: "d"})),
        holding(4., objectItem, Failed({reason: "beyond_host"})),
      ],
    ),
    ~fresh=counting(),
    ~database=true,
    ~bucket=true,
  ) {
  | Ok(Apply({list, into, database, object})) =>
    deepEqual((into, database, object, list.generation), (1., Some(2.), Some(5.), 4.))
    deepEqual(
      list.items->Array.map(i => (i.id, i.capacity)),
      [(1., Listing.capacity), (2., databased), (5., newObject)],
    )
    let credentials =
      list.items->Array.flatMap(i => i.credentials->Array.map(c => c->TypedArray.get(0)))
    deepEqual(Set.fromArray(credentials)->Set.size, 3)
  | Ok(Held(_)) | Error(_) => ok(false, ~message="no list planned")
  }
)

test("a build declaring no bucket leaves the object items it finds alone", () =>
  deepEqual(
    Listing.planned(
      described(
        1.,
        [
          holding(1., Listing.capacity, Made({address: "a"})),
          holding(2., objectItem, Made({address: "o"})),
        ],
      ),
      ~fresh=counting(),
      ~database=true,
    ),
    Ok(
      Apply({
        list: {
          generation: 2.,
          items: [
            {id: 1., capacity: Listing.capacity, credentials: [credentialOf(1)]},
            {id: 2., capacity: objectItem, credentials: [credentialOf(2)]},
            {id: 3., capacity: newDatabase, credentials: [credentialOf(3)]},
          ],
        },
        into: 1.,
        database: Some(3.),
        records: None,
        object: None,
      }),
    ),
  )
)
