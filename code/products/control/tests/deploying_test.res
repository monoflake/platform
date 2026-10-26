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

test(
  "a bucket is asked past every id, each item asked restated, and one asked is held",
  async () => {
    let fresh = () => credential
    deepEqual(
      Deploying.bucketPlanned(
        described([holding(1., Made({address: "10.0.0.2"})), holding(4., Unasked({since: 1.}))]),
        ~fresh,
      ),
      Apply({
        list: {
          generation: 4.,
          items: [
            {id: 1., capacity: Deploying.capacity, credentials: [credential]},
            {id: 5., capacity: Object({size: Deploying.bucketSize}), credentials: [credential]},
          ],
        },
        into: 5.,
      }),
    )
    let bucket: Contracts.ManagementHolding.t = {
      id: 2.,
      capacity: Object({size: 1.}),
      state: Making,
    }
    deepEqual(
      Deploying.bucketPlanned(described([holding(1., Making), bucket]), ~fresh),
      Held({into: 2.}),
    )
  },
)

test(
  "a release runs as its kinds or its form's, and the first of them offered is chosen",
  async () => {
    deepEqual(
      (
        Deploying.runsAs(~kinds=None, ~form=Modules),
        Deploying.runsAs(~kinds=None, ~form=Component),
        Deploying.runsAs(~kinds=None, ~form=Image),
        Deploying.runsAs(~kinds=Some([]), ~form=Image),
      ),
      ([Contracts.DeploymentKind.Function], [Function], [Container], []),
    )
    deepEqual(
      (Deploying.offered(described([])), Deploying.offered({...described([]), kinds: [Object]})),
      ([Contracts.ManagementKind.Function, Container], [Object]),
    )
    let offered: array<Contracts.ManagementKind.t> = [Function, Instance, Container]
    deepEqual(
      (
        Deploying.chosen(~runs=[Instance, Container, Function], ~offered),
        Deploying.chosen(~runs=[Instance], ~offered),
        Deploying.chosen(~runs=[], ~offered),
      ),
      (Some(Contracts.DeploymentKind.Container), None, None),
    )
  },
)
