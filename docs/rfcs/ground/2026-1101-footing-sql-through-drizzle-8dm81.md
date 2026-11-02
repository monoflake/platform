---
name: 'Footing SQL Through Drizzle'
title: The footing's tables are defined once in the model, and Drizzle queries them inside the footing
status: decided
supersedes: []
references: []
---

## Question

The footing is the one component that stands on the vendor's database, RFC 8yl4b, and every other
component reaches it through its interface, RFC n8jq5, so it is where SQL is written. Today the
control writes SQL by hand against D1, in strings no type ties to the tables its migrations make,
and its rows are decoded by hand. When the footing is built, and when an app of ours keeps a
database, is the SQL written by hand, through an ORM, or generated, and where are the tables defined
once?

## Options

- Drizzle's TypeScript schema as the one definition, with ReScript types generated from it. It
  splits the definition from the model, which is the standard.
- No ORM: typed statements and row decoders generated from the model. One definition, but every
  query beyond the simplest is written by hand.
- The model as the one definition, generating Drizzle's schema, ReScript row types and the migration
  SQL, with Drizzle used for queries inside the footing alone. Taken.

## Decision

The author's, on 2026-11-02, after the control's hand-written SQL was read against this question.

- **The tables, their columns and the record kinds they hold are defined once, in the model.** A
  generator, built beside the envelope generator, writes from it Drizzle's TypeScript schema, the
  ReScript row types and the migration SQL that wrangler's D1 migrations apply.
- **Drizzle is used inside the footing alone**, in a small TypeScript part that writes the queries,
  as docs/method.md allows TypeScript where a library's surface is too wide to bind. The footing
  answers the rest of the platform through a narrow ReScript interface; no other component sees
  Drizzle or SQL.
- **Nothing changes in the control now.** Its hand-written SQL stays until the footing replaces it,
  RFC 8yl4b, since a port to Drizzle before then would be taken out again.
- If the footing's design leaves only a few generic tables, generated typed statements may serve
  without Drizzle; that is read when the footing is built, and recorded here if it changes.
