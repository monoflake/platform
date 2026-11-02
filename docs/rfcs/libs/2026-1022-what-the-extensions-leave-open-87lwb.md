---
name: 'What the Extensions Leave Open'
title: "What extensions* chose where RFC kd7f9 is silent: the quota where none is set, how a set's custody and a copy's availability compose, which places lie apart, a borrower's grace, a loan's quota and the binding token, and a failure's shape"
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

Left open by RFC kd7f9. Each is built as proposed here, in `code/libs/extensions`, held to
`tests/extensions/`; a decision either way changes the library and its samples, never the shape of
`bind`, `grace`, `quota`, `compose`, `apply`, `lend` and `borrow`. The paths in the bundle are RFC
ot812's and are not built.

Open, for the discussion that follows:

- **The quota where neither the binding nor its organization sets one is none**: no quota is in
  force, and what the binding may use is bounded by its host alone, as the placement reads the
  machine's free space. The other reading, a default as the grace's week is, has no number
  proposed. [C42]
- **How a set composes past RFC vr5lw's table.** Custody is the lowest member's, since a set the
  organization does not alone control in one member is not alone controlled. A pool or a keyed set
  composes no durability and a set of copies no availability, so each is its lowest member's; a
  store's availability across copies is RFC 13ixj's to say. A keyed set is recoverable at
  most across regions as across nodes. A set of no member composes to nothing. Where a level came
  from, declared or composed, is not answered yet, and the API that shows it is the control's.
  [C42]
- **Which places lie apart.** Two members lie apart in a domain where both name it and the names
  differ, or a wider domain does, a node lying in a site, a site in a zone and a zone in a region,
  so two nodes of one name in two sites are two nodes. A member naming nothing of a domain lies
  apart from no other in it, and `account` stands beside the others and widens none. [C42]
- **A borrower's grace is left unset**, so its own organization's is in force by `grace`, while RFC
  v7v3w keeps the host's grace the lender's. Whether the borrower's control or the lender's sends
  the loaned binding its policy decides between them, and waits on C3 with the rest of how a loan's
  binding is handed over. [C42]
- **A loan's quota is not held to its lender's**: `lend` copies the lender's binding as it stands
  and sets the quota lent, and neither the lender's quota in force nor the sum of what it lent
  bounds it, which the lender's own record of a loan, RFC ot812, may come to hold. [C42]
- **The binding token passes through sealed.** An `extension` holds its binding token sealed, so
  `bind` and `borrow` take it as the control sealed it and keep it as opaque bytes; every other
  credential reaches the library as its BLAKE3, as kd7f9 asks. [C42]
- **A failure's shape.** Both `bind` and `apply` name every refusal, the contracts' `invalid`:
  a grace past a year and relays of `some` naming none or one twice; an id listed twice, hashes
  counted apart from the record's credentials or other than one or two, and a hash or a token of
  other than 32 bytes. An item of another extension is passed over rather than refused, since the
  list is the organization's and one driver is sent its own. [C42]
