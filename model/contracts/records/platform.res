/**
 * The records the platform's control keeps, RFC v7v3w: who holds a thing is told by who may change
 * it, so an account's own settings are its record, what the platform alone decides of an
 * organization is the platform's record of it, and what is unique across owners is a kind whose
 * value is its key. An account's status and an organization's are the anchor's, b8f35, and its
 * certificate is compiled, never written.
 */
open Subset

let types: array<declared> = [
  // An account's own: its name shown; how many ways a sign-in asks, one at least; how long its
  // credential lives; the address the platform reaches the person at, verified and unique to no one;
  // and a password's hash and a TOTP seed, sealed, each where held, which check an account already
  // found and find none.
  {
    name: "account",
    def: Record([
      optional("name", 1, Prim(#string)),
      field("factors", 2, Prim(#uint32)),
      field("security", 3, Type("security")),
      field("email", 4, Prim(#string)),
      optional("password", 5, Prim(#bytes)),
      optional("totp", 6, Prim(#bytes)),
    ]),
    from: "v7v3w",
  },
  // A capability's value in an allowance, by its type in the vocabulary, 49qyg: yes or no, an amount
  // in its unit, one of a set, or some of it.
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
  // The lender's side of a loan: the extension it lent of, the organization it lent to, and the
  // quota; the borrower holds it as an extension, its lender named. A lease is a clock's lock.
  {
    name: "loan",
    def: Record([
      field("extension", 1, Id("extension")),
      field("borrower", 2, Id("organization")),
      field("quota", 3, Prim(#uint53)),
    ]),
    from: "v7v3w",
  },
  // A label to the organization holding it, written as v7v3w writes a label, never one reserved.
  {
    name: "label",
    def: Record([field("label", 1, Prim(#string)), field("organization", 2, Id("organization"))]),
    from: "v7v3w, vr5lw",
  },
  {
    name: "username",
    def: Record([field("username", 1, Prim(#string)), field("account", 2, Id("account"))]),
    from: "v7v3w",
  },
  {
    name: "sign-in-kind",
    def: Enum({choices: codes(["passkey", "github", "google", "apple", "email"]), ordered: false}),
    from: "v7v3w",
  },
  // A way an account is found by as it signs in: a passkey's credential id, a provider's id for the
  // user, or an address a link is sent to. A password and a TOTP code are checked once it is found.
  {
    name: "sign-in",
    def: Record([
      field("kind", 1, Type("sign-in-kind")),
      field("identifier", 2, Prim(#string)),
      field("account", 3, Id("account")),
    ]),
    from: "v7v3w",
  },
  // An index of which organizations an account is in, reported by each organization's control,
  // never the truth: lost, it is gathered again from them.
  {
    name: "membership",
    def: Record([field("account", 1, Id("account")), field("organization", 2, Id("organization"))]),
    from: "v7v3w",
  },
  // A domain to the organization holding it, and until when its proof holds, vr5lw.
  {
    name: "domain",
    def: Record([
      field("domain", 1, Prim(#string)),
      field("organization", 2, Id("organization")),
      field("until", 3, Prim(#uint53)),
    ]),
    from: "vr5lw",
  },
]

let contents: array<content> = [
  {half: #platform, kind: "account", version: 1, content: "account"},
  {half: #platform, kind: "organization", version: 2, content: "platform-organization"},
  {half: #platform, kind: "extension", version: 2, content: "extension"},
  {half: #platform, kind: "loan", version: 1, content: "loan"},
  {half: #platform, kind: "label", version: 1, content: "label", unique: [["label"]]},
  {half: #platform, kind: "username", version: 1, content: "username", unique: [["username"]]},
  {
    half: #platform,
    kind: "sign-in",
    version: 1,
    content: "sign-in",
    unique: [["kind", "identifier"]],
  },
  {
    half: #platform,
    kind: "membership",
    version: 1,
    content: "membership",
    unique: [["account", "organization"]],
  },
  {half: #platform, kind: "domain", version: 1, content: "domain", unique: [["domain"]]},
]
