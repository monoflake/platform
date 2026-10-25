/*** `Ids.drawn` held to the floor of RFC b8f35, below which no id is drawn. */
open Node

/** Draws given in turn, each asked of `random`, and the ids `kept` was asked to keep. */
let scripted = draws => {
  let left = ref(draws)
  let asked = []
  let random = () =>
    switch left.contents {
    | list{next, ...rest} =>
      left := rest
      next
    | list{} => JsError.throwWithMessage("no draw left")
    }
  let kept = async id => {
    asked->Array.push(id)
    true
  }
  (random, kept, asked)
}

test("a draw below the floor is drawn again, and the next at or above it is kept", async () => {
  let (random, kept, asked) = scripted(list{0., 16777215., 16777217.})
  let id = await Ids.drawn(~random, ~kind="app", kept)
  // A draw below the floor is never offered to be kept, so nothing is written for it.
  deepEqual((id, asked), (16777217., [16777217.]))
})

test("a draw of exactly the floor is kept", async () => {
  let (random, kept, asked) = scripted(list{16777216.})
  let id = await Ids.drawn(~random, ~kind="binding", kept)
  deepEqual((Ids.floor, id, asked, Ids.text(id)), (16777216., 16777216., [16777216.], "01000000"))
})

test("16 draws all below the floor give up as 16 conflicts do", async () => {
  let draws = ref(0)
  let (_, kept, asked) = scripted(list{})
  let random = () => {
    draws := draws.contents + 1
    16777215.
  }
  let thrown = switch await Ids.drawn(~random, ~kind="binding", kept) {
  | _ => None
  | exception JsExn(e) => e->JsExn.message
  }
  deepEqual(
    (thrown, draws.contents, asked),
    (Some("every one of 16 binding ids drawn is held already"), 16, []),
  )
})
