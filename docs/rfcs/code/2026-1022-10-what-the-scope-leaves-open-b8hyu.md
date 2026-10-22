---
name: 'What the Scope Leaves Open'
title: "What scope* chose where RFCs vuanj and kd7f9 are silent: a bundle holding no scope by the id asked, a deleted scope's reason, a scope not active refusing first, where a section is read, which vocabulary judges, and in which form a need is given"
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

Left open by RFC vuanj, which makes a scope a concept read through one library, and RFC kd7f9,
which has `scope*` run `fits` as a reader judges a need. Each is built as proposed here, in
`code/libs/scope`, held to `tests/scope/`; a decision either way changes the library and its
samples, never what a scope is.

Open, for the discussion that follows:

- **A bundle holding no scope by the id asked.** A reader asks for the scope a capability names;
  the bundle names one scope, so one of another is refused by the id it names, one holding no issuer
  section is refused as absent, and a section that is not one CBOR data item as `bundle-issuer`
  writes it is refused as malformed, where it stands from the bundle's `body`. [C43]
- **A deleted scope's reason.** `scope-status` names `suspended` and `deleted`, while the issuer's
  operations declare `suspended` alone. `scope*` keeps the two apart, so a reader stops a sweep on a
  deleted scope; a call to either answers `suspended` until an operation declares another. [C43]
- **A scope not active refuses before it is compared.** A suspended or deleted scope refuses every
  need, one its allowance gives among them, and its allowance is still read for a reader that shows
  it. [C43]
- **Where a section is read.** `scope*` decodes the issuer section from the bundle's `body` itself,
  deterministically as capability\* reads a payload. Every product reading its own section would do
  the same, so one reader of a section in envelope\* is the alternative, `scope*` then calling it.
  [C43]
- **Which vocabulary judges.** The model's, `Needs.model`, taken inside the library and never
  passed, so no two readers judge by different tables; a bundle naming a vocabulary other than the
  one a reader was built with is compat's, RFC wnqvu. [C43]
- **In which form a need is given.** As a record holds it, `allowance-value` decoded by envelope\*,
  so a reader converts nothing; the allowance it answers, filled with the defaults, and every
  failure are vocabulary\*'s values. [C43]
