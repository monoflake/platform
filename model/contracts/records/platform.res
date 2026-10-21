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
