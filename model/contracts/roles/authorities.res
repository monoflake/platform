/**
 * The authority's contract at both ends, what a control pulls and asks certified and the notice it
 * is sent, RFC 7xpd3. A record pulled is never older than the one held.
 */
open Subset

let types: array<declared> = [
  // What an organization binds of another's, known by its host and carrying no secret. More waits
  // on C3.
  {
    name: "authority-loan",
    def: Record([
      field("host", 1, Type("extension-host")),
      field("endpoint", 2, Prim(#string)),
      field("levels", 3, Type("placement")),
      field("place", 4, Type("extension-place")),
      field("quota", 5, Prim(#uint53)),
      field("address", 6, Prim(#bool)),
    ]),
    from: "7xpd3, v7v3w",
  },
  // The record pulled, signed by the authority, its generation, certificate, allowance, loans and
  // status.
  {
    name: "authority-record",
    def: Record([
      field("generation", 1, Prim(#uint53)),
      field("certificate", 2, Prim(#bytes)),
      field("allowance", 3, Map(Type("allowance-value"))),
      field("loans", 4, List(Type("authority-loan"))),
      field("status", 5, Type("scope-status")),
    ]),
    from: "7xpd3",
  },
  // The generation the control holds, none where it holds nothing yet.
  {
    name: "authority-pull",
    def: Record([optional("holding", 1, Prim(#uint53))]),
    from: "7xpd3",
  },
  {
    name: "authority-pulled",
    def: Record([field("record", 1, Prim(#bytes))]),
    from: "7xpd3",
  },
  // A working key to certify and what it signs, the issuer's capabilities or the bundle.
  {
    name: "authority-certify",
    def: Record([
      field("key", 1, Type("confirmation")),
      field("role", 2, Type("certificate-role")),
    ]),
    from: "7xpd3, b8f35",
  },
  {
    name: "authority-certified",
    def: Record([field("certificate", 1, Prim(#bytes))]),
    from: "7xpd3, b8f35",
  },
  // A notice that there is a generation to pull, and nothing else.
  {name: "notice", def: Record([field("generation", 1, Prim(#uint53))]), from: "7xpd3"},
  {name: "noticed", def: Record([]), from: "7xpd3"},
]

/** A record whose generation is below what the control holds is never answered. */
let interface_: interface_ = {
  name: "authority",
  version: 2,
  from: "7xpd3",
  operations: [
    op(
      "pull",
      "authority-pull",
      "authority-pulled",
      [("ahead", #rejected)],
      ~callers=[#organization, #component],
    ),
    op(
      "certify",
      "authority-certify",
      "authority-certified",
      [("role_refused", #rejected), ("suspended", #rejected)],
      ~callers=[#organization],
    ),
  ],
}

/** The control's end, a notice repeated until the generation it names is pulled. */
let notices: interface_ = {
  name: "notices",
  version: 1,
  from: "7xpd3",
  operations: [op("notice", "notice", "noticed", [], ~callers=[#authority])],
}
