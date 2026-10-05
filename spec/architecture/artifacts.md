# What is published, how it is addressed, and what may cache it

The corpus is compiled and published as objects by the web repository, which holds the site, its
compiler and `local`. The site reads them at request time and is rebuilt only when its own code
changes. The shape is the platform's, typed in `@monoflake/sdk/artifacts`. What the objects hold is
web's `spec/architecture/data.md`; how a reader reaches one is [delivery.md](delivery.md); what a _thing_ is as
opposed to a run of bytes is [resource.md](resource.md); this file is the shape they are addressed
by and the rules that fall out of it.

## One mutable root, and everything else immutable

The published corpus is a tree of objects that name each other by content hash, with exactly
one object at the top whose name does not change. Nothing else in it may be rewritten.

That is the whole design, and every rule below is a consequence of it:

- **An immutable object needs no invalidation.** Its key cannot denote different bytes, so a
  cached copy is correct forever and the edge may hold it for a year.
- **The root is the only thing that can go stale**, so the site's publication delay is one
  number rather than a policy per resource.
- **A republish is incremental by construction.** An edit changes the hash of the object it
  touched and of the root; every other object is byte-identical and is not uploaded.

The last of those is inherited rather than invented. web's `spec/i18n/segments.md`
already hashes a block after normalization, so a reflow or a restyle changes no id. Hashing the
compiled view extends that property one level up: reformatting the whole corpus publishes
nothing.

## The key says what may cache it

**A hash in the path, written as BLAKE3 truncated to 128 bits in 32 lowercase hex characters.**
An address carrying one is content-addressed and is answered `immutable`. An address carrying none
is not, and keeps an hour. Anything that is not an answer keeps five minutes.

The classifier is the rule. Nothing is looked up in a table and no route has to remember to ask
for a policy: it gets the right one from the shape of its own address. The test that this is
working is that a route added beside the others arrives with the right lifetime and no decision
in it.

**There are three tiers and there used to be two.** The middle one arrived with the addresses that
name rather than identify -- a permanent name, a proxied path -- and what it says is that the
thing behind a name can move, but not on this site's publication clock. Before it, those addresses
took the five minutes meant for refusals, which was a publication delay applied to something that
is not published here.

**The long life is conditional on the answer having one.** A `404` on a content-addressed key
means the object was not uploaded or has been swept, and neither is a fact worth keeping for a
year. Every failure is five minutes, whatever the address looks like.

**A `304` is not a failure, and reading the condition as "2xx" got that wrong.** A revalidation's
headers replace the stored response's, so five minutes on a `304` cuts a year-old copy down to
five every time a client checks it -- the exact opposite of what the answer means. Measured: a
conditional request for a content object came back `304, max-age=300`. It now comes back with the
year, and a `416` or a `404` still comes back with five minutes.

That cuts both ways and it is why publication has an order: a root that names an object nobody
uploaded yet produces a `404` that is then held for five minutes on a key that becomes valid a
second later. See "Publication is ordered" below.

### An exception has to carry a promise, and none does today

This section used to hold two. **Latin font subsets** were served under stable names for a year,
on the promise that re-subsetting would produce a new filename -- and 510 of the 524 published
chunks never needed it, because the CJK splitter had been naming its output by content hash all
along. The promise covered fourteen files and explained an exception for all of them.

Every chunk is now an object like any other, addressed `/object/{cid}.woff2`, and the year it
keeps is the year the shape of its name earns. Re-subsetting writes a different object at a
different address instead of overwriting a promised name, which is what the promise was asking
everyone to remember not to do.

An exception would be a name plus the promise that justifies it, and there is none today.
`/favicon.ico` was the one, keeping a year with no hash in it; it is the gateway's now, a `302` to
the mark it names, kept for the publication delay -- see [delivery.md](delivery.md), "A page
follows the name for the browser".

Any address wanting a long life without a hash has to arrive with its own promise, and the list
is meant to grow at about the rate it has: not at all.

Another site's icon was the standing example of an address that wanted one and was refused: it was
an alias-layer route rather than a CDN one, so it took that host's default of five minutes, which
was as fresh as the `/asset` answer behind it. **It stopped needing an exception by stopping being
a name.** An icon is a resource, a link card compiles to its rid, and what a page draws is an
object address like any other -- so the five minutes now sit on the record that names it and the
bytes keep the year the shape of their name earns. See [resource.md](resource.md), "The
catalog".

## The mutable root

`state/index.json` is the only object in the bucket whose bytes change under a fixed name. It
holds, for every article and standalone page, every locale view's metadata and the hashes of
the objects that carry that view's content.

**Only the API reads it.** Nothing else parses its format, which is what lets it change shape
without a second consumer to keep in step, and what makes the API the one answer to "what is
published right now".

It is not sharded. At the corpus's size a locale split would be arithmetic performed on a file
small enough to send whole, and a shard is a second thing to keep consistent. The question comes
back when the file stops being small, and not before.

## What is stored is what cannot be worked out

**A published object holds what nothing could derive from the rest of it**: what the author wrote,
and what took judgment to produce -- a heading's id, a summary, a translation, each of which a
person or a model had to be asked for. **What a function of the stored data gives back, every time,
is worked out where it is used**: a block's anchor is its kind and its place, so the page and the
compiler each number the blocks themselves, and nothing stores the result. See
web's `spec/architecture/anchors.md`.

The test is whether working it out needs anything the object does not hold. Storing what does not
is a second copy of a decision that can fall out of step with the first, and it changes the
published shape, which asks for a new `ARTIFACT_VERSION` for no new fact.

Some stored fields fail this test and predate it: a view's word count, a phone's title and the
table of contents are each worked out from the view at build. They stay until the shape is next
reworked, and are reworked by this rule then rather than piecemeal now.

## Which objects exist

| Type       | Holds                                                | Produced per     |
| ---------- | ---------------------------------------------------- | ---------------- |
| `content`  | One compiled view: meta, toc, blocks, summary, words | article x locale |
| `markdown` | The article source, served at `<url>.md`             | article          |

**Two types, and a whole-corpus document is not one of them.** `atom.xml`, `llms.txt` and
`sitemap.xml` are assembled by the site's Worker out of the API's answer and, for the feed, the
content objects that answer names.

The feed was published for a while and it is the shape a content-addressed store is worst at:
a document the size of the whole corpus, rewritten whenever any one article changes. Nine
locales at a quarter-megabyte each, per edit, immutable and never swept -- a one-line fix to an
image URL wrote 2.0 MB. What made it look necessary was the belief that a feed says something a
block does not. It does not: `feedHtml` in libs/sdk/artifacts is the whole difference, and every
field it reads is already in `content/{hash}.json`. `llms.txt` needs no object at all, being a
projection of the root the homepage answer already carries.

What a runtime document costs is one fetch per entry on a cold assembly. Those are immutable and
a year old at the edge, and the document itself is held for five minutes, so it is paid once per
five minutes rather than once per reader.

## Publication is ordered, and deletion is not part of it

Two phases, and the order is the whole of it:

1. Upload every immutable object, and confirm each is readable.
2. Write the root.

A root that arrives first names objects that are not there yet, and the previous section says
what that costs. Confirming before the flip is a step in the publish task rather than a
property of the transfer, because ordering within one `rclone` run is not something to rely on.

**Every tree is mirrored with `sync`, the content-addressed ones included.** This once read the
other way: the content-addressed prefixes were copied, because `sync` deletes what is no longer
local and that would remove objects a root still in somebody's cache is naming.

The window is real and the placement was wrong. A mirror that keeps what the source dropped
diverges from it permanently, invisibly and forever, in exchange for a window measured in
minutes -- and it bought nothing anyway, because the sweep behind it deleted with no delay at
all. The retention belongs where the timing is known, which is the sweep: an object is deleted
locally an hour after nothing names it, so by the time it reaches the mirror as a deletion it
has been unnamed for longer than any root is cached.

**Deletion wants the opposite order from upload, and the mirror goes as far as one run allows.**
An object must stop being named before it stops being readable, so a delete belongs after the new
root is up. `rclone` binds a delete to the transfer that discovered it and the objects transfer
must run first, so `--delete-after` is the reachable half: nothing leaves a bucket until that
transfer's uploads have landed, and a failed run leaves a superset rather than a hole. The rest
is the hour above.

A sweep is `local gc`'s existing shape: dry by default, listing what nothing references.

### An object is swept an hour after nothing names it

**Not when it is found unnamed -- an hour after it became unnamed**, and the difference is the
whole of it. A root is cached for five minutes, so for five minutes after a republish there are
readers holding a root that names objects the new one does not. Deleting on sight makes those
readers ask the CDN for keys that were valid when they were handed them, and a `404` on a
content-addressed key is the one answer this design cannot afford to have cached.

An hour is five minutes plus a margin large enough that nothing has to be precise about clocks,
and small enough that a sweep run twice in an afternoon still collects.

**A sweep cannot know when an object stopped being named, so the first run writes it down.**
`local gc` records what it found unnamed and when, and deletes on a later run only what has been
unnamed for the hour. That makes the first run of a pair a no-op by construction, which is also
what `--dry` already showed, so the shape of the command does not change.

The record of pending deletions is regenerable by waiting: losing it costs one more cycle and
nothing else, so it lives under `data/build/` with the other things a tool can rebuild.

**This is also what lets the mirror be a mirror.** The delay used to live in `mise run sync`,
which copied content-addressed objects instead of syncing them so the bucket would keep what the
local tree had dropped. That protected the same window from the wrong side: the bucket then
diverged from the local tree permanently, and the sweep still deleted with no delay at all. See
web's `spec/architecture/data.md`, "Publication is a path, not a rule".

## Drafts leave the corpus at publication, not at build

A draft is compiled like anything else and its objects go into the **same** tree as everything
else. What withholds it is that the published root does not name it; a second root, under
`data/bucket/draft/` and never mirrored, does.

**The object tree was never the boundary, and pretending it was hid that.** `refs::scan` has never
read the draft flag, so a draft's pictures and clips have always been derived and mirrored like any
other article's -- protected, in practice, by nobody knowing their content ids. Giving the compiled
body the same protection makes the arrangement uniform instead of adding a new risk: a 128-bit hash
of the bytes is not reachable without having been told it.

**The root is the one thing that turns a guessable name into an id**, which is why it is the thing
that is withheld. A slug is human-readable and easy to guess; `findArticle` maps one to a content
id. So the production API is given a root that does not contain drafts, rather than a root that
does plus a filter -- a forgotten filter publishes a draft, and there is no filter to forget.

That also keeps this boundary the one the mirror already enforces, from the other side: `sync`
names the two trees it transfers, and refuses outright a source that contains the draft tree.

**Development reads the draft root, and that is the whole of the difference.** `wrangler dev` binds
one directory, so `data/bucket/draft/` holds the draft root and one symlink to the published records;
the CDN's dev binding is the objects tree itself. Nothing is copied and nothing is mirrored twice.

## The API is the only thing that changes

What reads these objects for the site -- its API, the routes it answers, how a page asks and what
it does when the API cannot answer -- is the site's, and is web's `spec/architecture/site-api.md`.
This file holds the objects and their keys.

## Validation is heavy where it is free and light where it is not

The builder validates every object completely, in a process with no payload budget
(the workspace's `spec/code.md` puts local code on the other side of that line). What ships to
an edge is narrow:

- The **API** parses the root with a schema. It is small, it is read once per cache miss, and
  everything downstream trusts it.
- The **site** and the **browser** check an object's envelope -- version, slug, locale, hash --
  and trust the body.

The reasoning is the one web's `spec/i18n/segments.md` already gives for the span
fingerprint: the check exists to catch drift between a producer and a consumer that were
deployed at different times, not to resist an adversary. The producer is trusted; the version
skew is not.

**What the envelope check cannot do is worth stating, because it looks like it can.** `v.object`
strips unknown keys rather than rejecting them, so a producer emitting a field the type no longer
declares passes every consumer silently. That is not a hole to close -- a consumer cannot police a
producer it does not run -- it is the boundary of what this check is. Measured: a stale writer kept
emitting a `locale` on a page object after the field was dropped, which cost nine published objects
where one would do, and no consumer noticed or could have. What found it was a person reading the
builder.

### The envelope check is only as good as the version inside it

`ARTIFACT_VERSION` is the field the envelope check turns on, and its own comment states the job:
bumped when a producer and a consumer can no longer read each other, and the only thing that
tells a worker it is holding bytes it does not understand. Everything above depends on somebody
having moved it.

Nobody did. When a compiled `image` block stopped carrying `src`, `srcset`, `width` and `height`
and started carrying a rid under `resources`, the constant stayed at 1. Both generations of
object therefore declared the same version, the envelope compared 1 against 1 and passed, and a
site worker deployed ahead of the corpus dereferenced a field its own type declared required.
Every article carrying a picture answered 500; every article without one was fine, so the outage
read as three broken articles rather than as a stale corpus.

**A change to a published shape moves `ARTIFACT_VERSION` in the same commit.** That is now
checked rather than remembered: `mise run shape` fingerprints the published shapes and compares
the fingerprint to the version it was recorded against, and `verify` runs it. `mise run shape
--bump` raises the constant and records what it now means, so nobody has to pick the number;
`--record` writes down what the current version means without raising it.

The fingerprint is **deliberately coarse** -- the whole of `types.ts` plus the named published
shapes in `index.ts`, comments stripped -- so renaming a type asks for a bump the emitted bytes
did not need. That is the side to be wrong on. A bump nobody needed costs one republish; a
missing bump costs what it cost here, and bumping is one command.

**Bumping cannot happen at publication.** The constant is source the workers are built from, so
a publisher that raised it on its own would write a corpus no deployed worker had been compiled
to read -- the same failure, in the same direction. The order is: raise it in the source,
publish, then deploy.

### A build says how far the live corpus is from it, and does not refuse

The two halves move on separate schedules -- workers deploy from a push through CI, the corpus
moves when somebody runs `publish` -- and nothing measured the distance. `mise run generation`
reads the live root out of the metadata bucket and prints its version and publication time
beside the one this source expects. `publish` and `deploy-site` both ask first;
the site's Worker asks for its API too, which parses the root in full, where a generation it
cannot read is not a degraded page but every answer failing.

**It warns and never refuses.** The gap is normally minutes, closed by the publish that follows,
and a check that blocked on it would be wrong far more often than right. What it owes is a line
loud enough to find afterwards, which is why the live root's timestamp is in it. Not being able
to ask is not a failure either: it runs where rclone is configured and in CI where it is not,
and a deploy is not the place to discover a missing credential for a check.

`valibot` is the schema library, chosen over `arktype` and `zod` because the schema ships to a
browser and an edge runtime, because it is the type's source of truth and therefore has to be a
file a person can annotate, and because runtime validation speed -- the axis `arktype` is
strongest on -- is the axis this design spends least on. See web's `spec/issues/issues.md` for what is
still undecided around it.

## What happens when writing moves online

Two decisions are pinned to one event and are recorded here together, because when it arrives
they change together.

**The event:** an online editor exists and local editing is retired, so an article is written
through a request rather than to a file.

**Then `contents/` and the records beside it leave git.** They are in git today because they are
small, because a rollback of prose matters, and because nothing else backs them up. An online
write path has to answer backup and history itself, and once it does, the reason to hold them
here is gone. Until then they stay, which web's `spec/architecture/data.md` states as the rule and this file
states as the condition on it.

**And the API's storage separates from the CDN's.** Metadata would then be written by the cloud
rather than mirrored to it, which is the line web's `spec/architecture/data.md` draws between what the author
produces and what a visitor produces. D1 for one and R2 for the other follows from that line
moving, not from a preference about databases.

Neither is worth doing early. Both are cheap to do late, because the addressing above does not
depend on where the root is stored -- only on there being exactly one of it.
