/***
 * Content cut into pieces by FastCDC with normalized chunking at level 2, given in parts as it
 * arrives, as RFC b8f35 defines it. The model's interface, `docs/code.md`.
 */

/** 256 KiB, the least a piece holds but the last. */
let least: int

/** 1 MiB, where the mask changes, about the size of a piece. */
let normal: int

/** 4 MiB, the most a piece holds. */
let most: int

/** Content being cut. */
type t

/** Why content was not cut, a gear table not of 2,048 bytes. */
type refused = Gear

/** The cutting of one content, with the gear table its scope's salt derives,
 * `Keys.Derive.gear`. */
let make: (~gear: Uint8Array.t) => result<t, refused>

/** The next part of the content, and the length of every piece it ends in order. */
let push: (t, Uint8Array.t) => array<int>

/** The content ended, with the length of the piece it leaves, if any. */
let finish: t => option<int>
