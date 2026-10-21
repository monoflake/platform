---
name: 'What Step Zero Still Asks'
title: "Three drafts the blocks of step 0 wait on, kept together until each is decided and moves into its own: the footing's interface, a binding's token, and the interfaces of vocabulary*, wit* and extensions*"
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

Kept in one file while `docs/rfcs/` holds as many entries as a directory may, until the author
decides how it nests; each part becomes an RFC of its own when it is decided.

## The footing's interface

### Question

RFC b8f35 puts a footing on Cloudflare as D1 behind a footing Worker of the same account, reached
by a service binding from a Worker and over HTTPS with a capability from a machine; every write a
conditional statement, commits grouped into batches. `model/graph/records.res` says which half and
which component writes each kind, and `model/graph/components.res` draws every edge to
`footing(organization)` with the records and bundle sections it reads. What the footing Worker
answers is written nowhere: no interface names it, no library reaches it, and whether a component
sends SQL or calls operations is not said. blob and the issuer cannot be written until it is; the
executor, which stores nothing, RFC vuanj, needs none of it.

Found while reading, and to be settled with this: `records.res` names compute and the executor as
writers of `lease`, and neither has an edge to `record.lease`; vuanj says the executor stores
nothing.

### Proposed

Written by the agent on 2026-10-21 for the author to decide.

1. **The footing is an interface, `footing`, declared in the model as every other is**, `POST
   /footing/{operation}`, its answers `answer` envelopes, RFC ge55b, so the footing Worker on
   Cloudflare and whatever answers it on a machine are held to one set of samples, RFC p8e8k, and no
   component writes SQL against a schema it does not own. Four operations:
   - `read`: a record by kind and key, or a kind's records by a prefix of a unique key, a page at a
     time; each with its shell, the generation that wrote it among them.
   - `write`: records of one change, each conditional -- absent, or at the generation read -- applied
     all or none, answered `stale` where any condition failed, the generation it made given back.
   - `bundle`: the newest signed bundle and its generation, or a section of it, for a reader that
     verifies it, `capability*`, refusing a generation lower than one it read, RFC v7v3w.
   - `lease`: a lease taken, renewed or given up, by name, `until` set by the footing's clock and
     never a host's, answered `held` while another holds it.
2. **Who may write what is the capability's**: a call carries a capability whose rights name the
   kinds its caller writes, as `records.res` lists them -- a control its configuration and
   `generation`, `store`; blob its extent's four kinds; a tablet `writer`; whoever holds leases,
   `lease` -- so the data plane's writing no configuration is held where it is written, not trusted.
3. **A machine reaches the same interface**: a host on a machine calls the footing Worker over
   HTTPS, RFC b8f35, and a footing on a machine, where one is, answers the same operations; the
   machine footing's engine is the machine's, behind them.
4. **`lease` is written by compute alone for now**: the executor stores nothing, vuanj, so it
   leaves `records.res`'s writers of `lease`, and compute gains the `record.lease` edge it lacks.

### Open

What a reader caches of a bundle, and how soon it sees a newer one, stays C36's. How long a read
may be stale, given D1's read replicas need a session's bookmark, `docs/lessons/cloudflare.md`, is
for when the footing Worker is written.

## A binding's token

### Question

RFC vr5lw decides who makes a binding's token and who keeps it: its control makes it, the host's
holder enters it in the driver's own management -- on a machine, a file `monoflake.driver.bindings`
names -- and the driver shows it once and keeps it salted and hashed, never the token itself; every
management call carries it. What the token is, as bytes and as text, how it is salted and hashed,
and how a call carries it are written nowhere, and the machine driver's management cannot take its
first binding without them.

### Proposed

Written by the agent on 2026-10-21 for the author to decide.

1. **A token is 32 random bytes and the binding's id, written as one text**:
   `monoflake-binding-1.<id>.<secret>`, the id the binding's `capacity` space's integer in decimal
   and the secret base64url unpadded, RFC fhg6w. A versioned prefix lets a holder, a log scrubber
   and a secret scanner know one on sight, as C24 asks of a key's comment; the id lets a
   driver find the binding a token is for without trying every hash.
2. **A driver keeps the id and `BLAKE3(salt || secret)`**, a salt of 16 random bytes of its own per
   binding. The secret is random and long, so a fast hash with a salt is enough, and no
   password-hashing cost is paid on every call.
3. **A call carries it as `Authorization: Bearer <token>`**, over the driver's HTTPS, or over the
   tailnet where the machine is reached only there; a token absent or not matching is `denied`, RFC
   ge55b, the same for a binding that does not exist, so a caller learns nothing of which.
4. **A file holds one token and nothing else**, so a secret manager writes it whole; the driver
   reads each file at start and on a signal, takes a token it has not seen, and forgets a binding
   whose file is gone only when its control has ended it, `end`, so a file lost never ends what runs.
5. **Replacing a token is a second one beside the first**, as an item's credential is, vr5lw: the
   driver holds both until the control's next list names only the new one.

### Open

Whether the token also names where its control is reached, so a driver could report to it rather
than wait to be asked, is left until a driver needs to call its control at all; today every call
goes from the control to the driver.

## The interfaces of vocabulary*, wit* and extensions*

### Question

`model/graph/libraries.res` names three libraries the control, compute, the issuer, the executor
and the host use, and says in a line what each is; their interfaces, which the model owns, are
unwritten. What each must do is settled across RFCs 49qyg, vuanj, v7v3w and vr5lw; what is left is
the shape, and where that shape stops.

### Proposed

Written by the agent on 2026-10-21 for the author to decide. Each is pure: it reads what its caller
hands it, decoded by `envelope*`, and reaches no store, no clock and no network, so every reader in
both runtimes judges alike.

1. **vocabulary\*, capabilities by name, type and rule**, RFC 49qyg: one table of entries, each a
   name, a type -- yes or no, an amount, one of a set, some of a set, as `allowance-value` holds
   them -- a rule and a default; the entries settled today, `kind`, `network`, `instance` and
   `export`, and one more added later changing nothing that compares. Two comparisons, each naming
   the capability that fails: `fits`, a need against an allowance, which the control runs as a
   change gives an app a version and `scope*` as a reader judges a need; and `meets`, a need
   against an offer, which the executor and placement run to choose a host. Defaults are filled
   before either, so an absent need is its default's.
2. **wit\*, an export's types and a call checked against them**, RFCs 49qyg and vr5lw: WIT read from
   a build manifest's `wit`, the component model's language as far as the subset taken; the
   exports and their signatures; a call matched to the export it names by its parameters' number
   and types, never their values; an export removed or changed that something calls, named; and a
   value converted between its JSON and its CBOR by the type both ends hold, as vr5lw's table writes
   each, refused where it does not parse as that type. The control runs the change-time checks and
   compute the conversion; cycles stay the control's.
3. **extensions\*, a control's extensions**, RFCs v7v3w and vr5lw: what both controls compute alike
   of the `extension` and `capacity` records -- a binding made from its host, its levels and place
   copied; its grace and quota in force, the organization's where its own is unset; the levels a set
   of members compose to, from those at `stable` and above; the `management-apply` a list of
   capacity becomes, each credential hashed; a loan's two records; and the paths to each host,
   fewest jumps first, for the bundle. Sealing, tokens and every call stay in the control.

### Open

The WIT subset's resources, `own` and `borrow`; the capabilities past those four, C11; an
export's amounts, C37; what a host offers, which waits on `?roster`. Each is a field or an entry
added, not a change of these shapes.
