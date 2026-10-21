/***
 * The generator, `model/graph/tools.res`: it reads `model/contracts.json` and writes envelope*'s
 * ReScript, one source, `generated/contracts.res` of the library, which `mise run generate` writes
 * by this package's `src/main.res`: `node src/main.res.mjs <contracts.json> <the library's
 * generated/>`, exiting 1 with the reason where it is not read. What that source holds, and every
 * name in it, is said by the library's `src/malformed.resi`. The model's interface, `docs/code.md`;
 * `src/lib.rs` is the same in Rust.
 */

/** `model/contracts.json`, read. */
type contracts

/**
 * Why the contracts were not read or written: where in them, as a path of names and indices joined
 * by `/`, and what was expected there.
 */
type unread = {at: string, expected: string}

/** The contracts in the text, as `model/contracts.json` is written. */
let read: string => result<contracts, unread>

/** envelope*'s ReScript: one source, the same for the same contracts byte for byte. */
let rescript: contracts => result<string, unread>
