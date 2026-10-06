# Issues: scheduling

What [../architecture/scheduling.md](../architecture/scheduling.md) leaves open. The rules over an
entry are the index's; see [issues.md](issues.md).

## What a bucket declares about losing its data

Neither of the two obvious answers holds. A durability in nines is a number nobody here can derive:
a store would carry a figure somebody typed in, and the sum would be as precise as the guess. A
count of copies has no reference either: three copies on one account are one copy to an account
that ends, and one copy in a provider's bucket already survives a dead disk.

**Proposed: a bucket declares which failures it must survive, and the copies are derived.** The
failures are few and anybody can name them:

| Failure   | Means                                        | Survived by                                                             |
| --------- | -------------------------------------------- | ----------------------------------------------------------------------- |
| `medium`  | a disk dies                                  | two copies on two media, or one on a store redundant by itself          |
| `domain`  | an account ends, or the house goes           | copies in two failure domains                                           |
| `mistake` | a deletion, or a bug that rewrites good data | history kept for a while -- snapshots or versions, which copies are not |

A store then says two things a person knows: its failure domain, already declared for every node,
and whether it is redundant by itself -- a provider's bucket and a mirrored pool are, a lone disk is
not. No figure is typed in anywhere. Derived data, which can be made again, survives nothing and
keeps one copy. Providers frame their classes the same way: S3's One Zone classes survive a disk
and not the loss of a zone. Undecided until the author agrees.
