---
name: 'One Database, One App'
title: "An app's database is an abstraction of two kinds by what it is used for -- transactional, in SQLite's dialect, run a statement or a batch at a time atomically, and analytical, appended and scanned -- known by an id that never changes, under a name an owner may move, bound to one app alone"
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

The platform is to give an app three stable things -- functions to run in, a database and a
storage -- and keep everything beneath them its own. Worked out with the author on 2026-10-15, top
down from what an app needs, before any implementation and apart from every earlier design of the
platform's databases; how it lands is left for after the functions are settled too. The question
here is the database's shape as an app sees it. The storage's is RFC 13ixj.

This is layer 0, the platform's face, as RFC vuanj numbers the layers.

The shape the discussion has reached so far, to be decided once it is diffed against what exists:

**`database` is the product, an abstraction: what runs it is the platform's and may change.** It
has two kinds, named for what each is used for and never for the engine beneath, as a function's
kinds are -- RFC 49qyg:

| Kind            | Used for                                             | Engine beneath, a library   |
| --------------- | ---------------------------------------------------- | --------------------------- |
| `transactional` | an app's own data, read and changed, atomically      | `sqlite*`, RFC b8f35        |
| `analytical`    | what is appended and scanned, never changed in place | one to be chosen, not built |

Neither engine is offered whole -- what an app gets is narrower than SQLite and narrower than any
analytical engine -- so an engine can be replaced under a kind whose name still fits.

**A `transactional` database**, whose contract is **SQLite's dialect**, so any engine that speaks it
serves it without translation:

- `execute(database, [statements])` runs one statement or several, each its SQL and parameters, and
  answers each one's rows; a call is atomic, all or nothing, with no state in between. **There is no interactive transaction.**
- It can be returned to any minute of the last 30 days, by what its implementation keeps, and past
  them to a snapshot it was asked to keep, RFC vuanj.
- **Past 30 days nothing is kept until its owner turns it on**, decided by the author on
  2026-10-20, so a database takes no more than it must. Turned on, it is given tiers each sparser
  as it grows older -- a snapshot a day to 90 days, a week to 180, a month to a year, about 79 in
  all -- which its owner changes as it likes within a year at most and one an hour at most,
  `model/contracts/records/database.res`.
- **A rewind within 30 days is in place**, undone by the moment its answer names. **A snapshot is
  restored as a new database unless its owner asks it over the old one**, decided by the author on
  2026-10-20: a new one is bound to the same app and shown beside it, so nothing is lost until the
  owner chooses; over the old, what it held is lost, as the owner asked.
- **Read copies are a switch on the database.** Off, every read is current. On, a read without a
  cursor is no longer promised current and may be behind by about a minute, the bound to be fixed
  later; a read with a cursor is promised to see at least what that cursor names.
- **Atomicity holds within one database.** Nothing spans two, so an app keeps what changes together
  in one, and splits along its own lines what does not -- a database per conversation, per user --
  creating as many as it needs. **Creating one changes the organization's configuration**, whoever
  asks -- a person through a client, or the app's own code calling the configuration API -- so it is
  its organization's own control's, RFC v7v3w: while that control is lost a create answers
  `unavailable` and every database that exists goes on serving, and the authority lost changes
  nothing for it.

**A database is known by an id that never changes**, and an owner sees it by a name shown in its
organization's tree, RFC v7v3w, a path only as it is drawn. Renaming or moving it changes nothing
else; **policy and binding belong to the id**. Deleting the database deletes its id and its place in
the tree, refused while an app is bound to it, RFC 49qyg.

**A database's record is `model/contracts/records/database.res`**, worked out with the author on
2026-10-19: bound to one app as it is made, `read_copies` off unless set; its `copies`, one unless
asked and at most 5, a write done once a majority of them hold it and the database read-only with
fewer alive, decided by the author on 2026-10-20, RFC vuanj; its snapshots kept apart from its
implementation as many as its `snapshot_copies` and placed as a bucket is, RFC 13ixj, one unless
asked and so none beyond it; its snapshots past 30 days by its `retention`, none unless set; and
the levels the compute its writer runs on needs, RFC vuanj. A copy and a snapshot copy are
named apart, since the first holds every write as it is done and the second a moment of it.

**A database is bound to one app alone.** Another app reads or writes it only through that
app's own interface, never directly: its schema is an agreement only its app knows, and a second
reader would be broken by the first one's migration without being told. A bucket can be shared
because a file has no schema; a database cannot.

**A schema is changed in a migration, a time a deployment opens**, and not while an app runs.
**While the window is open the database is read-only**, decided by the author on 2026-10-20: the
version running reads as before and its writes answer `unavailable`, worth a retry, and the window
closes once the migration's script has run and the new version is ready. A change kept online in
two steps, the schema widened before it is narrowed, is the app's to make where it wants one, never
asked of it. A
migration may run a script of the user's own to carry data through a change that destroys its old
shape. **A database's rights are one**, worked out with the author on 2026-10-19: a capability to a
database grants reading, writing and changing the schema together, since D1, behind its adapter,
tells no statement's kind before it runs, RFC vr5lw, `docs/lessons/`. So that no app drops a table in
the course of its work is the app's own discipline, never the platform's to enforce.

**Not hidden sharding.** A statement is never split across databases behind the app's back: the
statements that split cleanly and the ones that do not look alike to the app, and the second kind
would fail or slow without a reason it could see.

**An `analytical` database** is for what is appended and scanned rather than updated, such as a
transparency log or metrics: `append(table, rows)`, a restricted `execute`, and deletion by a range
of time. Nothing needs it yet, so it is not built; its place is kept so that it comes as a kind of
`database`, never as something beside it.

Open, for the discussion that follows:

- Everything beneath the contract past what RFC vuanj settles for the tablet. [C12]
- The form of results and the limits on one query. [C12]
- The `analytical` kind's table definition and its query dialect, when something needs it. [C12]
- Whether a database, as a bucket is, may be deleted only while empty. [C12]
