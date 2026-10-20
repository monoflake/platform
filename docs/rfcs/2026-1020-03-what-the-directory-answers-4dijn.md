---
name: 'What the Directory Answers'
title: "The contract between a scope, its backing and the role that finds them: a scope's id, its status and where its backing is, a row never removed"
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

RFC 8lkuv names the anchor, as a scope and its backing need it, a role of its own, since the anchor
is the platform half's, the other repository's. What it holds is settled, RFC b8f35: a row a scope,
its id, its status of `active`, `suspended` or `deleted`, and a reference to where its backing is,
never removed so an id is never given twice. The edges from `scope` and `backing` to it are drawn,
and their contract is undeclared, `?anchor`.

## Open, for the discussion that follows:

- A row as it crosses: the id's form, RFC b8f35, the status, and what a reference to a backing is,
  as an address a scope's components can reach. [B39]
- When it is read and how fresh a reading must be: at deployment, as the edges have it, and how
  soon a suspension stops what it suspends. [B40]
- Whether opening, suspending, restoring and deleting are this contract's too, so a team running its
  own writes them against it, or only the platform's control calls them and the contract is the
  reading alone. [B41]
