/**
 * What of the platform half's records an organization's half reads, RFC 8lkuv: what the authority
 * alone decides of an organization, its allowance and its deletion, RFC v7v3w. An account is an id
 * here and nothing more; its record, and every other the platform's control keeps, is
 * monoflake/cloud's.
 */
open Subset

let types: array<declared> = [
  // A capability's value in an allowance, by its type in the vocabulary, 49qyg: yes or no, an
  // amount in its unit, one of a set, or some of it.
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
  // What the platform alone decides of an organization, kept under its scope's id: its allowance,
  // each capability by its name, `export` among them, vuanj; and when its deletion was asked,
  // emptied as it is withdrawn, which the platform carries out even with the organization's own
  // control gone, b8f35. Nothing of another platform is here: a platform knows itself alone, 94y0d.
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
