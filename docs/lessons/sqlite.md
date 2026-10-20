# SQLite

Facts on SQLite at the sizes a tablet reaches, each with its source; see `README.md`.

## SQLite at size, read 2026-10-18

**SQLite's file is bounded by its pages, and the file system comes first.** "The maximum size of a
database file is 4294967294 pages": about 17.5 TB at the default 4 KiB page, about 281 TB at 64 KiB,
the latter "untested"; the default page count has been that maximum since 3.45.0. A growth past it
returns `SQLITE_FULL`, as does a file system's own limit, "usually much less". A table holds 2^64
rows in theory, and at 281 TB "no more than approximately 2e+13". Asked of what bounds a footing,
RFC b8f35. Source: https://www.sqlite.org/limits.html

**SQLite advises a client/server database once content nears a terabyte.** "For device-local storage
with low writer concurrency and less than a terabyte of content, SQLite is almost always a better
solution"; "when the size of the content looks like it might creep into the terabyte range, it
would be good to consider a centralized client/server database"; one writer at a time. Source:
https://www.sqlite.org/whentouse.html

**SQLite has been run at billions of rows**: 10 billion rows in 447 GB fully cached in 1 TB of
memory at 4 million queries a second, and 30 billion in 1.3 TB, past memory, on a modified SQLite;
and about 8.9 billion in 426 GB on an SSD, inserted in 6 hours and indexed in 8. Sources:
https://use.expensify.com/blog/scaling-sqlite-to-4m-qps-on-a-single-server and
https://sqlite-users.sqlite.narkive.com/KjYJgmcU/sqlite-boosting-insert-and-indexing-performance-for-10-billion-rows

**Keys in random order insert an order of magnitude slower once a table outgrows its cache.** On an
i7-9700K with NVMe, 5 million keys went in at 3,030,000 rows a second in order and 161,000
shuffled; 10 million random keys at 306,000 with a cache of 2,000 pages and 988,000 with
2,000,000. Random inserts grow faster than linearly while the table is larger than the cache, then
linearly once nearly every access misses. Asked of the extent, whose keys are hashes. Source:
https://voidstar.tech/sqlite_insert_speed/

**D1 names no page size.** Its compatible PRAGMA statements include `table_list`, `table_info`,
`index_list`, `quick_check`, `foreign_keys` and `optimize`, among others, and none of `page_size`,
`page_count`, `cache_size` or `mmap_size`. Source: https://developers.cloudflare.com/d1/sql-api/sql-statements/
