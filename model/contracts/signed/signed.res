/**
 * The signed records, RFC b8f35: a capability, a certificate and an account credential, each a
 * claim set of CWT, RFC 8392, and a bundle, a record and no token. What the platform adds to CWT's
 * claims takes labels below -65536, IANA's range for private use; `iat` and `exp` are CWT's
 * NumericDate, seconds, the one time the platform counts in seconds, as the standard is taken
 * whole.
 */
open Subset

/**
 * The claims CWT registers that the platform's records hold, by name and number, RFCs 8392, 8747.
 */
let registered = [("sub", 2), ("exp", 4), ("iat", 6), ("cnf", 8)]

let types: array<declared> = [
  {
    name: "cose-key-type",
    def: Enum({choices: [{name: "okp", code: 1}], ordered: false}),
    from: "RFC 9053",
  },
  {
    name: "cose-curve",
    def: Enum({choices: [{name: "ed25519", code: 6}], ordered: false}),
    from: "RFC 9053",
  },
  // An Ed25519 public key as COSE writes one, its labels COSE's.
  {
    name: "cose-key",
    def: Record([
      field("kty", 1, Type("cose-key-type")),
      field("crv", -1, Type("cose-curve")),
      field("x", -2, Prim(#bytes)),
    ]),
    from: "RFC 9052, b8f35",
    keys: #standard,
  },
  // The key a certificate certifies, as RFC 8747 confirms one.
  {
    name: "confirmation",
    def: Record([field("key", 1, Type("cose-key"))]),
    from: "RFC 8747",
    keys: #standard,
  },
  {
    name: "rights",
    def: Flags([
      {name: "read", code: 1},
      {name: "create", code: 2},
      {name: "replace", code: 4},
      {name: "delete", code: 8},
      {name: "alter", code: 16},
      {name: "call", code: 32},
    ]),
    from: "b8f35, vuanj",
  },
  {
    name: "certificate-role",
    def: Enum({
      choices: codes(["intermediate", "issuer", "bundle", "account", "component", "authority"]),
      ordered: false,
    }),
    from: "b8f35",
  },
  // What a capability reaches: a resource, by its id, which carries its type, so any kind of the
  // organization's; or a product's blob space, which a component's own work reaches alone, b8f35.
  {
    name: "capability-target",
    def: Union({
      tag: "name",
      cases: [
        {name: "resource", code: 1, fields: [field("id", 1, Across(#organization, "*"))]},
        {name: "space", code: 2, fields: [field("space", 1, Type("blob-space"))]},
      ],
    }),
    from: "b8f35",
  },
  // `sub` is the account, app or component it was given to, logged and never checked.
  {
    name: "capability",
    def: Record([
      field("iat", 6, Prim(#uint53)),
      field("exp", 4, Prim(#uint53)),
      field("sub", 2, Prim(#string)),
      field("scope", -65537, Across(#platform, "organization")),
      field("target", -65538, Type("capability-target")),
      field("rights", -65539, Type("rights")),
    ]),
    from: "b8f35",
    keys: #cwt,
  },
  // A scope's own certificate names it; one of the platform's own names none. A component's says
  // who it is, its name in the model as `sub`, and never what it may do, which its verifier's rules
  // say; each running instance holds a key of its own, b8f35.
  {
    name: "certificate",
    def: Record([
      field("iat", 6, Prim(#uint53)),
      field("exp", 4, Prim(#uint53)),
      optional("sub", 2, Prim(#string)),
      field("cnf", 8, Type("confirmation")),
      optional("scope", -65537, Across(#platform, "organization")),
      field("role", -65540, Type("certificate-role")),
    ]),
    from: "b8f35",
    keys: #cwt,
  },
  {
    name: "account-credential",
    def: Record([
      field("iat", 6, Prim(#uint53)),
      field("exp", 4, Prim(#uint53)),
      field("sub", 2, Prim(#string)),
    ]),
    from: "b8f35",
    keys: #cwt,
  },
  // A bundle: its generation, and an organization's the platform's it was compiled with; the
  // certificates a component reads a `kid` in, each signed; and its body, each product's section in
  // the product's own format, by the product's name.
  {
    name: "bundle",
    def: Record([
      field("version", 1, Prim(#uint32)),
      field("scope", 2, Across(#platform, "organization")),
      field("generation", 3, Prim(#uint53)),
      optional("platform", 4, Prim(#uint53)),
      field("certificates", 5, List(Prim(#bytes))),
      field("body", 6, Map(Prim(#bytes))),
    ]),
    from: "b8f35, v7v3w",
  },
  {
    name: "grant-target",
    def: Union({
      tag: "name",
      cases: [
        {name: "app", code: 1, fields: [field("id", 1, Id("app"))]},
        {name: "bucket", code: 2, fields: [field("id", 1, Id("bucket"))]},
        {name: "database", code: 3, fields: [field("id", 1, Id("database"))]},
      ],
    }),
    from: "vuanj",
  },
  // A grant: what an app may reach, and with which rights, compiled from its bindings, never
  // written.
  {
    name: "grant",
    def: Record([
      field("app", 1, Id("app")),
      field("target", 2, Type("grant-target")),
      field("rights", 3, Type("rights")),
    ]),
    from: "vuanj",
  },
  // A store as the blob and the extent reach it, its secret never here: its implementation of the
  // object kind holds that, deployed for it, b8f35.
  {
    name: "backing-store",
    def: Record([
      field("store", 1, Prim(#string)),
      field("address", 2, Prim(#string)),
      field("weight", 3, Prim(#uint32)),
      field("levels", 4, Type("placement")),
      field("place", 5, Type("extension-place")),
    ]),
    from: "b8f35",
  },
  // A scope's backing, a concept and never a process: its stores, and while they change the stores
  // before, read from until what those held has moved, b8f35.
  {
    name: "bundle-backing",
    def: Record([
      field("stores", 1, List(Type("backing-store"))),
      optional("before", 2, List(Type("backing-store"))),
    ]),
    from: "b8f35",
  },
  // Whether a scope runs, one type wherever it is said: its directory's row, its authority's record
  // and its bundle, which never says deleted, since a scope deleted has none, 4dijn, 7xpd3.
  {
    name: "scope-status",
    def: Enum({
      choices: [
        {name: "active", code: 1},
        {name: "suspended", code: 2},
        {name: "deleted", code: 3},
      ],
      ordered: false,
    }),
    from: "4dijn, vuanj",
  },
  // The issuer's section of a bundle: the grants, the allowance it reads, and the organization's
  // `security`, by which it dates what it signs, vuanj; and the scope's status, which every product
  // reads with its allowance through `scope*`, a scope being a concept and never a process, `active`
  // where absent.
  {
    name: "bundle-issuer",
    def: Record([
      field("grants", 1, List(Type("grant"))),
      field("allowance", 2, Map(Type("allowance-value"))),
      field("security", 3, Type("security")),
      optional("status", 4, Type("scope-status")),
    ]),
    from: "vuanj",
  },
]

let signed: array<signed> = [
  {name: "capability", version: 2, form: #claims, content: "capability"},
  {name: "certificate", version: 1, form: #claims, content: "certificate"},
  {name: "account", version: 1, form: #claims, content: "account-credential"},
  {name: "bundle", version: 1, form: #record, content: "bundle"},
  {name: "authority", version: 1, form: #record, content: "authority-record"},
  {name: "directory", version: 1, form: #record, content: "directory-row"},
]

/**
 * A bundle's sections, by the name of what reads each, decided by the author on 2026-10-20, RFC
 * b8f35: what the data plane reads of its organization's configuration and nothing a control alone
 * reads, each kind of record in one section at most, and no secret, which reaches a deployment
 * alone. A section is compiled from the records, never one of them: where a record holds a secret,
 * the section holds the rest.
 */
let sections = [
  ("issuer", "bundle-issuer"),
  ("backing", "bundle-backing"),
  ("storage", "bundle-storage"),
  ("database", "bundle-database"),
  ("compute", "bundle-compute"),
  ("gateway", "bundle-gateway"),
  ("hosts", "bundle-hosts"),
]
