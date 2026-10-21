/**
 * An organization's control's configuration API, one set of operations over every kind, each change
 * a generation, RFC v7v3w. A handle is resolved to its id as it is received.
 */
open Subset

/** The kinds a change may write, in the order the model declares them, so a code is never moved. */
let kinds: array<(string, string)> =
  Records.own
  ->Array.filter(r =>
    r.half == #organization && r.writes == ["control(organization)"] && r.kind != "generation"
  )
  ->Array.filterMap(r =>
    Array.flat([Storage.contents, Database.contents, Compute.contents, Control.contents])
    ->Array.find(c => c.half == #organization && c.kind == r.kind)
    ->Option.map(c => (r.kind, c.content))
  )

/** A union with a case for each kind, its fields made of the kind's id and content. */
let byKind = (name, fields: (string, string) => array<field>, from): declared => {
  name,
  def: Union({
    tag: "kind",
    cases: kinds->Array.mapWithIndex(((kind, content), i) => {
      name: kind,
      code: i + 1,
      fields: fields(kind, content),
    }),
  }),
  from,
}

let types: array<declared> = [
  // A record written, its id or a handle, the generation it was read at, and its content whole or
  // none to delete it.
  byKind(
    "change-item",
    (kind, content) => [
      optional("id", 1, Id(kind)),
      optional("handle", 2, Prim(#string)),
      optional("read", 3, Prim(#uint53)),
      optional("content", 4, Type(content)),
    ],
    "v7v3w",
  ),
  {
    name: "change",
    def: Record([
      field("items", 1, List(Type("change-item"))),
      optional("reverts", 2, Prim(#uint53)),
      optional("dry_run", 3, Prim(#bool)),
    ]),
    from: "v7v3w",
  },
  // A warning, its kind, what it is about, when it was raised, what it says and the generation that
  // dismissed it.
  {
    name: "warning",
    def: Record([
      field("kind", 1, Prim(#string)),
      field("about", 2, Prim(#uint32)),
      field("raised", 3, Prim(#uint53)),
      field("says", 4, Prim(#string)),
      field("dismissible", 5, Prim(#bool)),
      optional("dismissed", 6, Prim(#uint53)),
    ]),
    from: "v7v3w",
  },
  {
    name: "record-key",
    def: Record([field("kind", 1, Prim(#string)), field("id", 2, Prim(#uint32))]),
    from: "v7v3w",
  },
  // A dry run has no generation. Each handle of the change given its id; what it changed; the
  // warnings it raises; and whether it was deployed wherever it goes before the answer was given.
  {
    name: "changed",
    def: Record([
      optional("generation", 1, Prim(#uint53)),
      field("ids", 2, Map(Prim(#uint32))),
      field("changed", 3, List(Type("record-key"))),
      field("warnings", 4, List(Type("warning"))),
      field("deployed", 5, Prim(#bool)),
    ]),
    from: "v7v3w, vr5lw",
  },
  // A record as a generation holds it, its content absent once deleted.
  byKind(
    "record",
    (kind, content) => [
      field("id", 1, Id(kind)),
      field("generation", 2, Prim(#uint53)),
      field("version", 3, Prim(#uint32)),
      optional("content", 4, Type(content)),
    ],
    "v7v3w",
  ),
  // One record of a kind by its id or its path, as the current generation holds it unless one is
  // named.
  {
    name: "record-read",
    def: Record([
      field("kind", 1, Prim(#string)),
      optional("id", 2, Prim(#uint32)),
      optional("path", 3, Prim(#string)),
      optional("generation", 4, Prim(#uint53)),
    ]),
    from: "v7v3w",
  },
  {name: "record-found", def: Record([field("record", 1, Type("record"))]), from: "v7v3w"},
  // A kind's records by id, after `after`, at most `limit`, a thousand unless set.
  {
    name: "record-list",
    def: Record([
      field("kind", 1, Prim(#string)),
      optional("after", 2, Prim(#uint32)),
      optional("limit", 3, Prim(#uint32)),
      optional("generation", 4, Prim(#uint53)),
    ]),
    from: "v7v3w",
  },
  {
    name: "record-listed",
    def: Record([field("records", 1, List(Type("record"))), optional("next", 2, Prim(#uint32))]),
    from: "v7v3w",
  },
  // A generation, its number, its footing time, its actor's `sub` and the generation it went back
  // to.
  {
    name: "generation-row",
    def: Record([
      field("number", 1, Prim(#uint53)),
      field("time", 2, Prim(#uint53)),
      field("actor", 3, Prim(#string)),
      optional("reverts", 4, Prim(#uint53)),
    ]),
    from: "v7v3w",
  },
  {
    name: "generation-list",
    def: Record([optional("after", 1, Prim(#uint53)), optional("limit", 2, Prim(#uint32))]),
    from: "v7v3w",
  },
  {
    name: "generation-listed",
    def: Record([
      field("generations", 1, List(Type("generation-row"))),
      optional("next", 2, Prim(#uint53)),
    ]),
    from: "v7v3w",
  },
  {name: "generation-of", def: Record([field("number", 1, Prim(#uint53))]), from: "v7v3w"},
  // Where a generation goes, each target as its driver or bundle reports it.
  {
    name: "deployment-target",
    def: Record([field("target", 1, Prim(#string)), field("deployed", 2, Prim(#bool))]),
    from: "v7v3w",
  },
  {
    name: "generation-status",
    def: Record([
      field("generation", 1, Type("generation-row")),
      field("targets", 2, List(Type("deployment-target"))),
    ]),
    from: "v7v3w",
  },
  {
    name: "warning-list",
    def: Record([optional("about", 1, Prim(#uint32))]),
    from: "v7v3w",
  },
  {
    name: "warning-listed",
    def: Record([field("warnings", 1, List(Type("warning")))]),
    from: "v7v3w",
  },
  // A dismissal is configuration, kept on what it is about, so it is a generation as any change is.
  {
    name: "warning-dismiss",
    def: Record([field("kind", 1, Prim(#string)), field("about", 2, Prim(#uint32))]),
    from: "v7v3w",
  },
  {
    name: "warning-dismissed",
    def: Record([field("generation", 1, Prim(#uint53))]),
    from: "v7v3w",
  },
]

/**
 * A change is checked against all the control holds, stale reads, dangling handles, broken rules
 * and placements, and an app's manifest, 49qyg.
 */
let interface_: interface_ = {
  name: "configuration",
  version: 1,
  from: "v7v3w, vr5lw",
  operations: [
    op(
      "change",
      "change",
      "changed",
      [
        ("stale", #rejected),
        ("unresolved", #rejected),
        ("depended_on", #rejected),
        ("invalid", #rejected),
        ("unplaceable", #rejected),
        ("beyond_allowance", #rejected),
        ("calls_unmatched", #rejected),
        ("call_cycle", #rejected),
      ],
    ),
    op("read", "record-read", "record-found", [("no_kind", #rejected), ("not_found", #rejected)]),
    op("list", "record-list", "record-listed", [("no_kind", #rejected)]),
    op("generations", "generation-list", "generation-listed", []),
    op("generation", "generation-of", "generation-status", [("not_found", #rejected)]),
    op("warnings", "warning-list", "warning-listed", []),
    op(
      "dismiss",
      "warning-dismiss",
      "warning-dismissed",
      [("not_found", #rejected), ("not_dismissible", #rejected)],
    ),
  ],
}
