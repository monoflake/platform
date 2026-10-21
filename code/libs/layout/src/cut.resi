/***
 * Content cut into pieces by FastCDC with normalized chunking at level 2, RFC b8f35, written down by
 * its definition and never by a library's version, since two implementations cutting one byte apart
 * deduplicate nothing between them; its parameters never change. Content is given in parts, as it
 * arrives, so a file is never held whole. The model's interface, `docs/code.md`.
 *
 * Within each piece, the byte at offset `i` from its start:
 * - below `least`, is taken and not hashed; the hash is 0 as a piece begins;
 * - from `least`, is hashed, `hash = (hash << 1) + gear[b]`, wrapping at 64 bits, `gear[b]` the
 *   eight bytes at `8b` of the gear table, little-endian; and the piece is cut after it, holding it,
 *   when `hash & mask` is 0, `mask` the 22-bit `0x0000d93767537000` while `i` is below `normal`, and
 *   the 18-bit `0x0000d90707537000` from it;
 * - at `most - 1`, ends the piece whatever its hash.
 * What is left once the content ends is one piece, however short, and content shorter than `least`
 * is one piece; empty content is none.
 */

/** 256 KiB, the least a piece holds but the last. */
let least: int

/** 1 MiB, where the mask changes, about the size of a piece. */
let normal: int

/** 4 MiB, the most a piece holds. */
let most: int

/** Content being cut. */
type t

/** Why content was not cut: a gear table not of 2,048 bytes. */
type refused = Gear

/** The cutting of one content, with the gear table its scope's salt derives,
 * `Keys.Derive.gear`. */
let make: (~gear: Uint8Array.t) => result<t, refused>

/**
 * The next part of the content, and the length of every piece it ends, in order: each piece's
 * bytes are the part's and those before it since the last piece ended.
 */
let push: (t, Uint8Array.t) => array<int>

/** The content ended: the length of the piece it leaves, if any. */
let finish: t => option<int>
