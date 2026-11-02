---
name: 'What the Vocabulary Leaves Open'
title: "What vocabulary* chose where RFC kd7f9 is silent: a group's member on the wire, a need's one of a set left absent, what is held read leniently, which side compares which entry, an amount's unit, and how the table is read"
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

Left open by RFC kd7f9. Each is built as proposed here, in `code/libs/vocabulary`, and the table
it reads is `vocabulary` in `model/contracts/records/platform.res`; a decision either way changes
the library and its samples, `tests/vocabulary/`, never the shape of `fits` and `meets`.

Open, for the discussion that follows:

- **A group's member on the wire.** `allowance-value` holds no group, so each member of `export` is
  held as an `amount` keyed `export.{member}` in the same map, and a value at the group's own name
  is mistyped. A case of its own, `amounts`, would change `allowance-value` and so raise the
  bundle, the authority's record and the platform's organization with it. [C40]
- **A need's one of a set, left absent, asks nothing.** An entry's default is what a side holding
  nothing of it holds; for one of a set that is some of it, the allowance's or the offer's, so a
  need has none to take. `kind` is always given by the manifest's own field; the sandbox is given
  by the executor as it chooses one. [C40]
- **The sandbox's default is none.** A host offering no sandbox meets no need of one, and an
  allowance holding none refuses a need naming one, which no need reaching `fits` does today. [C40]
- **What is held is read leniently, a need strictly.** An entry, a member of a set or a group's
  member that an allowance or an offer holds and the vocabulary does not name is passed over, so
  an entry or a member added later changes no older reader's answer; a need naming one is refused,
  unknown or mistyped. [C40]
- **Every entry is compared at both, by its default where a side holds nothing.** An offer holding
  no `export` refuses a need of any, an allowance holding no sandbox a need of one; whether some
  entries are compared only at `fits` or only at `meets` is not said. [C40]
- **An amount's unit.** RFC 49qyg gives an amount its unit; the table holds none, since no amount
  is settled yet, `export`'s members among them [C37]. [C40]
- **How the library reads the table.** It imports `model/contracts.json` whole as a JSON module,
  reaching outside its package as envelope's `build.rs` does, rather than a generator writing the
  table into the library as `envelope-generator` writes envelope's. [C40]
