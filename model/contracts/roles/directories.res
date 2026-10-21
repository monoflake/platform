/**
 * The directory's contract, RFC 4dijn: a scope's row, read and never written, by what reads its
 * backing, each call signed by its certificate, and read as it is deployed alone. A row is a record
 * the authority signs, so whatever carries it -- this read, or the deployment of what reads it -- it
 * is verified the same way. A row is never removed: a scope deleted answers as deleted, and only an
 * id never opened is not found.
 */
open Subset

let types: array<declared> = [
  // A scope's row: its id, its status, and the place in a footing where its backing is kept, which
  // its components can reach.
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
