/***
 * CBOR, RFC 8949: one data item as its data model has it, written as its 4.2.1 writes it and read
 * strictly. The model's interface, `docs/code.md`; `src/interface.rs` is the same in Rust.
 */

/**
 * One data item. An integer is any of -2^64 to 2^64 - 1, of major type 0 or 1 by its sign, and is
 * never a float: a float is kept as the double it denotes, whichever width it was read at. A map
 * keeps its pairs in the order read, any value a key. A tag and a simple value are kept as they
 * are written, a simple value one of 0 to 19 and 32 to 255.
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
  /** The input ended inside an item: RFC 8949 Appendix F's first kind. */
  | Truncated
  /** Bytes were left after the one item: its second kind. */
  | Trailing
  /**
   * A syntax error, its third kind: a reserved value, a simple value below 32 in two bytes, a
   * string chunk not a definite string of its own type, a break out of place, or additional
   * information 31 on major type 0, 1 or 6.
   */
  | Syntax
  /** Well formed yet not valid: text that is not UTF-8, or a map's key repeated, its 5.3 and 5.6. */
  | Invalid
  /**
   * Well formed and valid, yet not as 4.2.1 writes it: an indefinite length, a head or a float
   * longer than it need be, a NaN but f97e00, or a map's keys out of the bytewise order of their
   * encodings. Only `decodeDeterministic` refuses this.
   */
  | Nondeterministic

/** Why a value could not be written: an integer, a tag or a simple value out of its range. */
type unwritable = OutOfRange

/**
 * The value written as RFC 8949's 4.2.1 writes it: definite lengths, every head and float in its
 * shortest form, a NaN as f97e00, and every map's keys in the bytewise order of their encodings.
 */
let encode: value => result<Uint8Array.t, unwritable>

/** Exactly one data item, well formed and valid. */
let decode: Uint8Array.t => result<value, refused>

/** Exactly one data item, as `decode` reads it, and only one `encode` would write byte for byte. */
let decodeDeterministic: Uint8Array.t => result<value, refused>
