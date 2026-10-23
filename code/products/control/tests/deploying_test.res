/*** `Deploying` held to RFC vr5lw, the binding's list given a container only where it has none. */
open Node
module Contracts = Envelope.Contracts

let holding = (id, state): Contracts.ManagementHolding.t => {
  id,
  capacity: Deploying.capacity,
  state,
}
let described = (items): Contracts.ManagementDescribed.t => {
  generation: 3.,
  policy: 0.,
  grace: 0.,
  items,
}
let credential = Uint8Array.fromLength(32)

test("a container is asked past every id held, at the next generation, where none is", async () =>
  deepEqual(
    Deploying.planned(described([holding(2., Unasked({since: 1.}))]), ~credential),
    Ok(
      Apply({
        list: {
          generation: 4.,
          items: [{id: 3., capacity: Deploying.capacity, credentials: [credential]}],
        },
        into: 3.,
      }),
    ),
  )
)

test("a container asked already is held, and a list asking only others is refused", async () => {
  deepEqual(Deploying.planned(described([holding(5., Making)]), ~credential), Ok(Held({into: 5.})))
  let volume: Contracts.ManagementHolding.t = {id: 1., capacity: Volume({size: 1.}), state: Making}
  ok(Deploying.planned(described([volume]), ~credential)->Result.isError)
})
