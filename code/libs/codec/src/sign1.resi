/***
 * COSE's Sign1, RFC 9052's 4.2: one signer's signature over a payload and its protected headers.
 * The signature is made and checked by what the caller gives, over `toBeSigned`; this holds the
 * structure alone. The model's interface, `docs/code.md`.
 */

/** A Sign1 as its four fields. */
type t = {
  /**
   * The protected header map as the bytes it was serialized to, RFC 9052's 3, an empty map as no
   * bytes: kept as written, since the signature covers these bytes and not a map.
   */
  protected: Uint8Array.t,
  unprotected: array<(Cbor.value, Cbor.value)>,
  /** None where the payload is detached, written as nil, its 4.1. */
  payload: option<Uint8Array.t>,
  signature: Uint8Array.t,
}

/** Why bytes were not read as a Sign1. */
type refused =
  /** Not one CBOR data item, as `Cbor.decode` refuses it. */
  | Cbor(Cbor.refused)
  /**
   * One data item, yet no Sign1: a tag other than 18, or not an array of a byte string, a map, a
   * byte string or nil, and a byte string.
   */
  | Shape

/**
 * The bytes a signature is made and checked over, the Sig_structure for "Signature1", RFC 9052's
 * 4.4: its context, the protected bytes, the external additional data and the payload, written as
 * `Cbor.encode` writes them.
 */
let toBeSigned: (
  ~protected: Uint8Array.t,
  ~aad: Uint8Array.t,
  ~payload: Uint8Array.t,
) => Uint8Array.t

/** The Sign1 written as `Cbor.encode` writes, under tag 18 where `tagged`. */
let encode: (t, ~tagged: bool) => result<Uint8Array.t, Cbor.unwritable>

/** A Sign1, under tag 18 or under none, and whether it was tagged. */
let decode: Uint8Array.t => result<(t, bool), refused>
