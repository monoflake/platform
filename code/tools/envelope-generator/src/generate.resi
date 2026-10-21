/***
 * The generator, which writes envelope*'s `generated/contracts.res` from `model/contracts.json` as
 * `docs/envelope.md` lays out. The model's interface, `docs/code.md`.
 */

/** `model/contracts.json`, read. */
type contracts

/**
 * Why the contracts were not read or written, where by names and indices joined by `/`, and what
 * was expected.
 */
type unread = {at: string, expected: string}

/** The contracts in the text, as `model/contracts.json` is written. */
let read: string => result<contracts, unread>

/** envelope*'s ReScript, one source, the same for the same contracts byte for byte. */
let rescript: contracts => result<string, unread>
