# Scope

What the model covers in its current version. An edge case outside it goes to the out-of-model list
and is not designed for until a later version takes it in. See `spec/process.md`.

## v0

**Dimensions.** Each edge carries:

- when it is needed: `start`, `serve`, `deploy` or `background`;
- what its loss does: `hard`, wrong or stopped, or `soft`, slower, staler or more garbage and never
  wrong.

A `hard` edge points to its own layer or below; a `soft` edge may point up. A library uses only
libraries.

**Checks.** Bootstrap, the order the `start` edges allow from the ground up. Upgrade, what replaces
each part. Recovery, what stops when one running part is lost, by the `hard` `serve` edges.

**Failure model.** One part crashes and restarts, one at a time. One store is lost.

**Out of the model in v0:** performance and cost; more than one failure at once; corrupted data; a
machine acting against the rest; a clock that is wrong; a network split in two.

Open, for v0:

- Whether the owner of a data contract -- who defines the format a part reads -- is a dimension of
  its own. The issuer reads the function product's rows from a tablet: the call points down, the
  format it must understand is defined above.
- Sorting each boundary the model has found into: decided now, since a mistake is written into data
  and cannot be undone; done by hand on day one, with its command; or left for later, with what
  brings it back.
