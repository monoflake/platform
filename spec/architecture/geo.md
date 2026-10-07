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

**The data is GeoLite2 City and ASN, taken from a mirror's releases**: the GitHub releases of
`P3TERX/GeoLite.mmdb`, which republishes MaxMind's files as `.mmdb` without a license key, so no key
lives anywhere here. The answer credits MaxMind as its license asks.

## GeoLite2 is fetched as the image is built

**Both data sets are fetched by the image build and travel inside the image, read-only; geo asks
nothing of the network at run time.** GeoLite2 arrives the way GeoNames does, by `ADD` of its
address in the Dockerfile, and lands in `/data` beside the place index. A copy of geo is whole the
moment it starts, on any node: one without IPv4 receives the image the way it receives every
other, through the egress proxies -- infra's `spec/architecture/nodes.md`, "The nodes" -- and never
reaches GitHub itself. A file that cannot be opened ends the process at start, like a missing place
index, so the deploy fails and the previous version answers on.

**The data is as new as the last build.** Any push touching geo rebuilds it, and `deploy.yml`
rebuilds geo alone on the first of each month. How often it should be rebuilt, and by whom, is open
-- [../issues/scheduling.md](../issues/scheduling.md), "How often geo's data is rebuilt".

Rejected: **geo fetching GeoLite2 itself, once a day, into a data directory of its own**, which was
how it began. A node without IPv4 could not reach the mirror, so `/geo/ip` answered `503` there,
and every node's first minutes answered `503` until its first download landed. Decided on
2026-10-07.

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

