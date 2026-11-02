/*** The rules run over a graph of their own, each finding once. */
open Testing

let node = (layer, edges): Components.component => {layer, edges, uses: []}
let to = (to_, when_, ~contract=?) =>
  Components.e(to_, when_, Components.hard, "made here", ~contract?)

let over = (components): Base.graph => {
  components,
  own: components,
  fillers: _ => [],
  records: [],
}

test("a cycle is found once however many hard edges join its nodes, each hop's edges named", () => {
  let g = over(
    dict{
      "a": node(0, [to("b", #serve), to("b", #deploy, ~contract=["one", "two"])]),
      "b": node(0, [to("a", #serve), to("a", #start), to("a", #deploy, ~contract=["three"])]),
    },
  )
  let found = Rules.check(g).violations
  deepEqual(
    found->Array.map(v => v.text),
    ["hard cycle: a -> b -> a, by a -> b serve, deploy one+two; b -> a serve, start, deploy three"],
  )
  deepEqual(found->Array.map(v => v.at), [["a", "b", "a"]])
})

test("a component of one half reaching the other half's footing by any edge is reported", () => {
  let footing = (half): Components.component => {
    layer: -3,
    half,
    answers: ["footing"],
    edges: [],
    uses: [],
  }
  let g = over(
    dict{
      "footing(organization)": footing(#organization),
      "footing(platform)": footing(#platform),
      "mine": {...node(-2, [to("footing(organization)", #serve)]), half: #organization},
      "theirs": {...node(-2, [to("footing(platform)", #deploy)]), half: #organization},
      "control": {...node(-2, [to("footing(platform)", #serve)]), half: #platform},
    },
  )
  let found =
    Rules.check(g).violations->Array.filter(v =>
      v.text->String.startsWith("stands on the other half's footing")
    )
  deepEqual(found->Array.map(v => v.at), [["theirs"]])
})
