# `geo`: where a place is, and where an address is

`apps/compute/geo` answers two questions from data it maps from disk: which place is near a position,
`/geo/address`, from GeoNames; and where an IP address is, `/geo/ip`, from MaxMind's GeoLite2.
Both are public scopes of the API host: CPU alone, and cheap enough to answer anyone, within the
limits every public route has.

## `/geo/ip`: an address, looked up

**`GET /geo/ip?address=<ip>` answers the address's country, region, city, approximate position and
time zone, and its network's ASN and organization**; without `address` it looks up the caller's
own, which the gateway passes on as `Cf-Connecting-Ip`. IPv4 and IPv6 alike. An address the data
does not know answers with what it does know and nulls for the rest; one that is not an address is
`400`. It is limited per caller like `/geo/address`, in the service's `[[api.limits]]`, which the
gateway and Caddy both keep -- [services.md](services.md), "A limit is declared once and kept in
three places".

**The data is GeoLite2 City and ASN, taken daily from a mirror's releases**: the GitHub releases of
`P3TERX/GeoLite.mmdb`, which republishes MaxMind's files as `.mmdb` without a license key, so no key
lives anywhere here. The answer credits MaxMind as its license asks.

**geo fetches it itself, at run time, once a day**, into its own data directory: a new file is
downloaded beside the one in use, opened and read once to prove it whole, and swapped in atomically,
so a lookup never meets half a file and a failed download leaves yesterday's answering. It is read
memory-mapped, so the page cache holds what is asked and the heap nothing. A daily image rebuild
was the other way, and was not taken: it would redeploy a large image every day for one file.

Until the first file has arrived, `/geo/ip` answers `503` and `/geo/address` is unaffected; the
image carries no copy, so a new node's first minutes ask for one.

## Both lookups are files laid out for asking, and the page cache keeps them

**Neither lookup parses its data into the heap; each reads a file built for the question, mapped
into memory.** GeoLite2 is such a file already. GeoNames is not -- tab-separated text -- so the image
build turns it into the place index `whereabouts` reads: points sorted along a space-filling curve,
positions as fixed-point integers in records of one width, names in one table the records point
into, and the time zones' polygons the same way, with each polygon's bounds. A lookup touches the
few pages around the point it asks for. **Nothing large is parsed into the heap, whatever its
size**: memory a lookup holds for good is a cost every node pays, and a mapped page is not.

**Which pages stay in memory is the kernel's to decide.** A page asked for is read from disk the
first time and kept while it is asked again; one nobody asks is the first the kernel takes back when
the container nears its limit. So geo's `memory_mb` covers what the program itself holds, and the
data costs memory only while it is being asked. Rejected: loading the data in parts and dropping
what has not been asked for a while, inside geo, which is the page cache written again by hand,
and rebuilding a tree on a cold request, which made that request wait seconds.

The raw GeoNames files stay in the build and never reach the image. Decided on 2026-10-07, when the
parsed GeoNames data held 455 MB of heap on every node running geo, against 63 MB of GeoLite2 pages
the kernel could reclaim.

