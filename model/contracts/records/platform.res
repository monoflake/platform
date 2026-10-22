/**
 * What an organization's half reads of the platform half's records, the authority's decisions of
 * its allowance and deletion, RFCs 8lkuv and v7v3w.
 */
open Subset

let types: array<declared> = [
  // A capability's value in an allowance by its type, yes or no, an amount, one of a set or some of
  // it, 49qyg.
  {
    name: "allowance-value",
    def: Union({
      tag: "name",
      cases: [
        {name: "flag", code: 1, fields: [field("value", 1, Prim(#bool))]},
        {name: "amount", code: 2, fields: [field("value", 1, Prim(#uint53))]},
        {name: "one", code: 3, fields: [field("value", 1, Prim(#string))]},
        {name: "some", code: 4, fields: [field("values", 1, List(Prim(#string)))]},
      ],
    }),
    from: "vuanj, 49qyg",
  },
  // What the platform alone decides of an organization, its allowance and when its deletion was
  // asked, carried out even without its control, b8f35.
  {
    name: "platform-organization",
    def: Record([
      field("allowance", 1, Map(Type("allowance-value"))),
      optional("deleting", 3, Prim(#uint53)),
    ]),
    from: "v7v3w, vuanj, 94y0d",
  },
]

let contents: array<content> = [
  {half: #platform, kind: "organization", version: 2, content: "platform-organization"},
]

/**
 * A capability's type and its default, what a side holding nothing of it holds, kd7f9. A set is a
 * declared enumeration by its name, and a group's members are each an amount.
 */
type capabilityType =
  | Flag({default: bool})
  | Amount({default: int})
  /** A need holds one member, compared with the members the other side holds. */
  | OneOf({set: string, default: array<string>})
  | SomeOf({set: string, default: array<string>})
  | Amounts({members: array<string>, default: int})

type capability = {name: string, type_: capabilityType, from: string}

/**
 * The vocabulary of capabilities a need, an allowance and an offer are written in, its rule
 * following its type, 49qyg and kd7f9.
 */
let vocabulary: array<capability> = [
  {
    name: "kind",
    type_: OneOf({set: "function-kind", default: ["derive", "effect"]}),
    from: "49qyg, kd7f9",
  },
  {
    name: "network",
    type_: SomeOf({set: "deployment-network", default: ["http"]}),
    from: "49qyg",
  },
  {name: "instance", type_: Flag({default: false}), from: "49qyg"},
  // Which amounts it groups is open [C37].
  {name: "export", type_: Amounts({members: [], default: 0}), from: "49qyg, 94y0d, kd7f9"},
  {name: "sandbox", type_: OneOf({set: "sandbox", default: []}), from: "kd7f9, vuanj"},
]
