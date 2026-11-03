/***
 * How the storage product names an object and what it holds in the `object` kind, RFC 13ixj. The
 * model's interface, `docs/code.md`.
 */

/** Which rule of an object's extension a write breaks, answered as `extension_invalid`. */
type broken =
  /** A character other than an ASCII letter, a digit or a dot. */
  | Character
  /** Empty, or past `longest` characters. */
  | Length
  /** A dot leading, trailing or doubled. */
  | Dot

/** The most characters an extension holds, RFC vuanj. */
let longest: int

/** What each broken rule says, as the refusal's message. */
let message: broken => string

/**
 * An extension made standard, lowered and its last part rewritten by the table of spellings, or the
 * first rule it breaks.
 */
let standard: string => result<string, broken>

/** An object's name, its hash as 64 lowercase hex and its standard extension after a dot. */
let object: (~hash: Uint8Array.t, ~extension: option<string>) => string

/** An object's name read back into its hash and extension, none where it is not one. */
type named = {hash: Uint8Array.t, extension: option<string>}

let parse: string => option<named>

/** The `object` kind's name of content, `content/{hash}`, held once for every object naming it. */
let content: Uint8Array.t => string

/** The prefix a bucket's objects are held under, its id as 8 lowercase hex and `/`. */
let bucket: float => string

/** The `object` kind's name of an object, empty, `{bucket}/{object}`. */
let marker: (~bucket: float, string) => string

/** The media type an object is served as, by its extension's last part, else octet-stream. */
let mediaType: option<string> => string
