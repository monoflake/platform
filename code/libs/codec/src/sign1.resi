/***
 * COSE's Sign1, RFC 9052's 4.2, its structure alone and its signature the caller's. The model's
 * interface, `docs/code.md`.
 */

/** A Sign1 as its four fields. */
type t = {
  /**
   * The protected header map as the bytes it was serialized to, kept as written since the signature
   * covers them.
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
  /** One data item yet no Sign1, by its tag, its shape or its protected bytes. */
  | Shape

/**
 * The Sig_structure for "Signature1" a signature covers, RFC 9052's 4.4, empty protected bytes
 * written as none.
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
