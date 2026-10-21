/***
 * CBOR, RFC 8949, one data item written as its 4.2.1 writes it and read strictly. The model's
 * interface, `docs/code.md`.
 */

/**
 * One data item. An integer is never a float, a float is the double it denotes, and a map keeps its
 * pairs in the order read.
 */
type rec value =
  | Integer(bigint)
  | Bytes(Uint8Array.t)
  | Text(string)
  | Array(array<value>)
  | Map(array<(value, value)>)
  | Tag(bigint, value)
  | Bool(bool)
  | Null
  | Undefined
  | Simple(int)
  | Float(float)

/** Why bytes were not read as one data item. */
type refused =
  /** The input ended inside an item, RFC 8949 Appendix F's first kind. */
  | Truncated
  /** Bytes were left after the one item, Appendix F's second kind. */
  | Trailing
  /** A syntax error, RFC 8949 Appendix F's third kind. */
  | Syntax
  /** Well formed yet not valid, text that is not UTF-8 or a map's key repeated, its 5.3 and 5.6. */
  | Invalid
  /**
   * Within more than `depth` arrays, maps and tags, refused as soon as it is met, so no input can
   * nest a reader into running out of its stack.
   */
  | TooDeep
  /** Well formed and valid yet not as 4.2.1 writes it, which only `decodeDeterministic` refuses. */
  | Nondeterministic

/** Why a value could not be written, what `decode` would refuse never being written. */
type unwritable =
  /** An integer, a tag or a simple value out of its range. */
  | OutOfRange
  /** A map holding two keys whose encodings are one. */
  | RepeatedKey
  /** A value within more than `depth` arrays, maps and tags. */
  | TooDeep

/** How many arrays, maps and tags an item may stand within, 128 as `DEPTH` is in Rust. */
let depth: int

/**
 * The value written as RFC 8949's 4.2.1 writes it, every length definite and every head shortest.
 */
let encode: value => result<Uint8Array.t, unwritable>

/** Exactly one data item, well formed and valid. */
let decode: Uint8Array.t => result<value, refused>

/** Exactly one data item, as `decode` reads it, and only one `encode` would write byte for byte. */
let decodeDeterministic: Uint8Array.t => result<value, refused>
