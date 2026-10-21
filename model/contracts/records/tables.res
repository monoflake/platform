/**
 * A footing's own tables, each keyed and holding one versioned CBOR record, RFC b8f35. A tablet's
 * rows are its product's schema instead.
 */
open Subset

let types: array<declared> = [
  // When a generation was taken, by the footing's clock as no host's is trusted; the `sub` of the
  // capability that asked; and the generation it goes back to, where it does, v7v3w.
  {
    name: "generation",
    def: Record([
      field("generation", 1, Prim(#uint53)),
      field("time", 2, Prim(#uint53)),
      field("actor", 3, Prim(#string)),
      optional("reverts", 4, Prim(#uint53)),
    ]),
    from: "v7v3w, b8f35",
  },
  // A store of the backing, where it answers, its sealed secret, its weight and the levels it
  // declared, 13ixj.
  {
    name: "store",
    def: Record([
      field("store", 1, Prim(#string)),
      field("address", 2, Prim(#string)),
      field("secret", 3, Prim(#secret)),
      field("weight", 4, Prim(#uint32)),
      field("levels", 5, Type("placement")),
      field("place", 6, Type("extension-place")),
    ]),
    from: "b8f35",
  },
  // The pieces a content is made of, in order.
  {
    name: "content",
    def: Record([field("hash", 1, Prim(#hash)), field("pieces", 2, List(Prim(#hash)))]),
    from: "b8f35",
  },
  // Where a piece lies, its parcel, offset and length, and whether it was compressed.
  {
    name: "piece",
    def: Record([
      field("hash", 1, Prim(#hash)),
      field("parcel", 2, Prim(#hash)),
      field("offset", 3, Prim(#uint53)),
      field("length", 4, Prim(#uint53)),
      field("compressed", 5, Prim(#bool)),
    ]),
    from: "b8f35",
  },
  // A parcel, named by its unkeyed hash, and the store it lies in where that is not the one its
  // place is computed to, until the repair moves it back.
  {
    name: "parcel",
    def: Record([field("parcel", 1, Prim(#hash)), optional("store", 2, Prim(#string))]),
    from: "b8f35",
  },
  // The journals a placement writes, one open and one frozen, each named by a random seed.
  {
    name: "journal",
    def: Record([
      field("placement", 1, Type("placement")),
      field("open", 2, Prim(#hash)),
      optional("frozen", 3, Prim(#hash)),
    ]),
    from: "b8f35",
  },
  // Which writer holds a tablet, at which generation; one of an older generation is refused.
  {
    name: "writer",
    def: Record([
      field("tablet", 1, Prim(#string)),
      field("holder", 2, Prim(#string)),
      field("generation", 3, Prim(#uint53)),
    ]),
    from: "vuanj, b8f35",
  },
  // A clock's lock, who holds a name and until when by the footing's clock.
  {
    name: "lease",
    def: Record([
      field("name", 1, Prim(#string)),
      field("holder", 2, Prim(#string)),
      field("until", 3, Prim(#uint53)),
    ]),
    from: "b8f35, v7v3w",
  },
]

let contents: array<content> = [
  {
    half: #organization,
    kind: "generation",
    version: 1,
    content: "generation",
    unique: [["generation"]],
  },
  {half: #organization, kind: "store", version: 2, content: "store", unique: [["store"]]},
  {half: #organization, kind: "content", version: 1, content: "content", unique: [["hash"]]},
  {half: #organization, kind: "piece", version: 1, content: "piece", unique: [["hash"]]},
  {half: #organization, kind: "parcel", version: 1, content: "parcel", unique: [["parcel"]]},
  {half: #organization, kind: "journal", version: 1, content: "journal", unique: [["placement"]]},
  {half: #organization, kind: "writer", version: 1, content: "writer", unique: [["tablet"]]},
  {half: #organization, kind: "lease", version: 1, content: "lease", unique: [["name"]]},
]
