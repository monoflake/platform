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
- It keeps a write-ahead log and can be returned to an earlier time.
- **Read copies are a switch on the database.** Off, every read is current. On, a read without a
  cursor is no longer promised current and may be behind by about a minute, the bound to be fixed
  later; a read with a cursor is promised to see at least what that cursor names.
- **Atomicity holds within one database.** Nothing spans two, so an app keeps what changes together
  in one, and splits along its own lines what does not -- a database per conversation, per user --
  creating as many as it needs. **Creating one changes the organization's configuration**, whoever
  asks -- a person in the console, or the app's own code calling the configuration API -- so it is
  its organization's own control's, RFC v7v3w: while that control is lost a create answers
  `unavailable` and every database that exists goes on serving, and the platform's control lost
  changes nothing for it.

**A database is known by an id that never changes**, and an owner sees it by **one name**,
`(path)/(database)`, a key split by `/`, which points at the id. Moving the name changes nothing
else; **policy and binding belong to the id**. Deleting the name deletes the database and its id,
refused while an app is bound to it, RFC 49qyg.

**A database is bound to one app alone.** Another app reads or writes it only through that
app's own interface, never directly: its schema is an agreement only its app knows, and a second
reader would be broken by the first one's migration without being told. A bucket can be shared
because a file has no schema; a database cannot.

**A schema changes only in a migration, a privileged time a deployment opens**, and never while an
app runs: no app drops a table in the course of its work. A migration may run a script of the
user's own to carry data through a change that destroys its old shape. Every right to a database
is separate -- read, insert, update, delete, and changing the schema -- each statement's kind known
before it runs, and the last is given to a migration alone.

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
