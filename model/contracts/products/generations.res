/**
 * An organization's control's interface, its configuration API, RFC v7v3w: one set of operations
 * over every kind of record it writes, never one a resource, so a kind added to the model is a case
 * more and the interface is otherwise unchanged. A change is a generation, a batch accepted whole or
 * refused whole, asked as a dry run or taken; going back is a change giving an older generation's
 * records again. What makes one resource of a kind, as a bucket is made, is a client's to draw.
 *
 * A handle stands for an id in what is sent, a path in the organization's tree or a name a change
 * gives a record it makes, and is resolved to the id as the request is received, a record made
 * given its id then: nothing past the control sees a handle, decided by the author on 2026-10-20.
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
  // A record written: its id where it is there already, or a handle for one made; the generation it
  // was read at, refused where it changed since; its content whole, or none, deleting it.
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
  // A warning, whatever raises it: its kind, a code; what it is about, an id of any kind; when it
  // was raised; what it says, from the API; and the generation that dismissed it, once one has.
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
  // A generation: its number, its time by the footing's clock, its actor's `sub`, and the
  // generation it went back to, where it did.
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
 * A change checked against the whole of what the control holds: a record read at a generation it
 * has changed since, a handle naming nothing, a record still depended on removed, content that
 * breaks its kind's rules, or a placement the scope's stores cannot meet. What an app's version
 * declares is held to the allowance as compute deploys it, which is the orchestration's [B32].
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
