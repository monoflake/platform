/***
 * An id of RFC b8f35 as the tools write and read it, 8 lowercase hex digits with no prefix, an
 * app's and a binding's alike. This file is its interface, the model's.
 */

/** The id written out, its 32 bits as an unsigned number, leading zeros kept. */
let text: float => string

/** The id 8 lowercase hex digits write, none for any other text or for 0, which no id is. */
let ofText: string => option<float>

/** The 32 bits of 4 bytes read big-endian, as an id is read from its bytes. */
let ofBytes: Uint8Array.t => float

/**
 * `--<flag> <id>` taken out of the arguments, the id where given and what is left, or why the
 * value given is no id.
 */
let taken: (array<string>, ~flag: string) => result<(option<float>, array<string>), string>
