/*** `Tree.unprovided` over a tree made here, RFC s42ex. */
open Testing

let held = (name, package): Blocks.held => {
  name,
  languages: [#rust],
  package,
  license: "MIT OR Apache-2.0",
  uses: [],
  takes: [],
  samples: [],
}

let tree: Blocks.tree = {
  root: Base.root,
  blocks: Map.fromArray([
    ("code/substrate/accepted", held("accepted(machine)", "accepted-machine")),
    ("code/substrate/working", held("working(machine)", "working-machine")),
  ]),
  work: dict{"accepted-machine": Work.Accepted, "working-machine": Work.InWork},
  rows: [],
}

test("a name whose block is accepted is provided", () =>
  deepEqual(Tree.unprovided(tree, ["accepted(machine)"]), [])
)

test("a name whose block is in work is refused", () =>
  deepEqual(
    Tree.unprovided(tree, ["working(machine)"]),
    ["working(machine): declared as provided, yet working-machine is not accepted"],
  )
)

test("a name no block is named for is refused", () =>
  deepEqual(
    Tree.unprovided(tree, ["absent(machine)"]),
    ["absent(machine): declared as provided, yet no block of this tree is named for it"],
  )
)
