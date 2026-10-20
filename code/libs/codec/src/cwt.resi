/***
 * A CWT, RFC 8392: a claims set, a CBOR map, carried as the payload of a Sign1, which may stand
 * under CWT's tag 61. What a claim means is the caller's; this holds the structure alone. The
 * model's interface, `docs/code.md`.
 */

/** A claims set, its pairs in the order read; a claim's key is an integer or a text, its 3. */
type claims = array<(Cbor.value, Cbor.value)>

/** Why bytes were not read as a CWT. */
type refused =
  /** Not under tag 61 nor anything else a Sign1, as `Sign1.decode` refuses it. */
  | Sign1(Sign1.refused)
  /** A Sign1 whose payload is detached, so it carries no claims. */
  | Detached
  /** A payload that is not one CBOR data item, as `Cbor.decode` refuses it. */
  | Payload(Cbor.refused)
  /** A payload that is one data item, yet no map. */
  | Unclaimed

/** The payload a Sign1 carries the claims as: the map written as `Cbor.encode` writes it. */
let payload: claims => result<Uint8Array.t, Cbor.unwritable>

/** A CWT's Sign1 and its claims, from bytes under tags 61 and 18, 18 alone, or neither. */
let decode: Uint8Array.t => result<(Sign1.t, claims), refused>
