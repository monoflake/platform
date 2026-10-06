# Issues: scheduling

What [../architecture/scheduling.md](../architecture/scheduling.md) leaves open. The rules over an
entry are the index's; see [issues.md](issues.md).

## Which words describe a store

A store is described by what it does rather than what it is made of, and providers already name the
dimensions: **durability**, the chance a year passes without losing an object, written in nines;
**availability**, the share of time it answers; and an **access tier** -- `hot`, `cool`, `cold`,
`archive` at Azure, Standard to Archive at Google, Standard to Glacier Deep Archive at AWS -- set by
how often data is read and how long the first byte may take. Which of these a store declares, and
which are measured, is undecided.

## How a copy at home is weighed against a copy at a provider

A disk at home holds one copy and fails at its disk's rate; a provider's bucket promises eleven nines
on its own. Counting copies treats the two as equal. Weighing them by durability -- the loss of an
object being every copy lost within the time a lost copy takes to replace -- does not, but only
covers losing a medium: an account that ends loses every nine at once, which is what the failure
domain is for. Whether a bucket declares copies, a durability, or both is undecided.
