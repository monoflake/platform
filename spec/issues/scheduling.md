# Issues: scheduling

What [../architecture/scheduling.md](../architecture/scheduling.md) leaves open. The rules over an
entry are the index's; see [issues.md](issues.md).

## How a copy at home is weighed against a copy at a provider

A disk at home holds one copy and fails at its disk's rate; a provider's bucket promises eleven nines
on its own. Counting copies treats the two as equal. Weighing them by durability -- the loss of an
object being every copy lost within the time a lost copy takes to replace -- does not, but only
covers losing a medium: an account that ends loses every nine at once, which is what the failure
domain is for. Providers write durability in nines -- eleven, for S3, R2 and Google's -- and keep availability, the
share of time an object can be read, as a separate figure; a store at home that is offline has lost
availability and none of its durability. Whether a bucket declares copies, a durability, or both is
undecided.

## A browser sends no header for what a page embeds

A private object is read with a header -- [../architecture/scheduling.md](../architecture/scheduling.md),
"Every object has a record, and access is decided on it" -- and an `<img>` or a `<video>` cannot set
one. A page that shows a private picture needs a cookie on the gateway's own domain or an address
signed for a while; the second is what [services.md](services.md), "A picture is served at its id,
to whoever holds it, for as long as it is kept", is waiting for. Which, or both, is undecided.
