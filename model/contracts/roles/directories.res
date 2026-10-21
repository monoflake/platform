/**
 * The directory's contract, a scope's row the authority signs, read by what reads its backing, RFC
 * 4dijn. A row is never removed.
 */
open Subset

let types: array<declared> = [
  // A scope's row, its id, its status and where in a footing its backing is kept.
  {
    name: "directory-row",
    def: Record([
      field("scope", 1, Across(#platform, "organization")),
      field("status", 2, Type("scope-status")),
      field("backing", 3, Prim(#string)),
    ]),
    from: "4dijn, b8f35",
  },
  {
    name: "directory-read",
    def: Record([field("scope", 1, Across(#platform, "organization"))]),
    from: "4dijn",
  },
  {name: "directory-answer", def: Record([field("row", 1, Prim(#bytes))]), from: "4dijn"},
]

let interface_: interface_ = {
  name: "directory",
  version: 1,
  from: "4dijn",
  operations: [op("row", "directory-read", "directory-answer", [("not_found", #rejected)])],
}
