/***
 * Every signed record verified, RFC b8f35: a COSE Sign1 of RFC 9052, tagged 18, by Ed25519, its
 * protected header `alg` -19, `kid` the first 16 bytes of the BLAKE3 of the signer's public key, and
 * `typ` its kind's; its payload its content's CBOR, read as `Codec.Cbor.decodeDeterministic` reads.
 * A signature is verified strictly, by RFC 8032 and never ZIP-215's encodings, so every runtime
 * answers one signature alike. A signer is found by its `kid` among the certificates given, a
 * call's `kcwt` among them, or as the root, and every certificate above it is verified so, to the
 * root. Nothing here reads a clock: a time is the caller's, in seconds. The model's interface,
 * `docs/code.md`.
 *
 * Who signs what, decided by the author on 2026-10-20, and nothing else:
 *
 * | Signer                 | Signs                                                                   |
 * | ---------------------- | ----------------------------------------------------------------------- |
 * | the root               | a certificate of `intermediate`                                         |
 * | `intermediate`         | a certificate of `authority`                                            |
 * | `authority`            | a certificate of `organization`, `issuer`, `bundle` or `account`; an    |
 * |                        | authority's record; a directory's row                                   |
 * | `organization`         | a certificate of `component`, with its `sub`; a call                    |
 * | `issuer`               | a capability                                                            |
 * | `bundle`               | a bundle                                                                |
 * | `account`              | an account credential                                                   |
 * | `component`            | a call                                                                  |
 *
 * A signer holding a scope signs only what holds the same: a certificate's and a capability's
 * `scope`, a bundle's. What carries `iat` and `exp` -- a certificate, a capability, an account
 * credential -- is refused from `exp` on, and while its `iat` is more than 60 seconds ahead, each
 * certificate of a chain as much as what it signs.
 */

/** What a signed record is, each by its `typ`. */
type kind =
  /** `monoflake:capability:2`. */
  | Capability
  /** `monoflake:certificate:1`. */
  | Certificate
  /** `monoflake:account:1`. */
  | Account
  /** `monoflake:bundle:1`. */
  | Bundle
  /** `monoflake:authority:1`. */
  | Authority
  /** `monoflake:directory:1`. */
  | Directory
  /** `monoflake:call:1`, whose payload is a call's CBOR, its certificate in `kcwt`, fhg6w. */
  | Call

/** The kind's `typ`. */
let typ: kind => string

/** What a record is verified against: the root's public key, 32 bytes; the certificates known, each
 * as signed, a bundle's among them; and the time, in seconds. */
type trust = {root: Uint8Array.t, certificates: array<Uint8Array.t>, now: float}

/** Who signed: the root, or a certificate's role, its scope where it holds one, and its `sub`. */
type signer =
  | Root
  | Signed({role: string, scope: option<float>, sub: option<string>})

/** Why a record is refused, the first of these as it is read, then its signer's, then above. */
type refused =
  /** Not a tagged Sign1, its header or its content not as its kind writes it, the why told. */
  | Malformed(string)
  /** An `alg` but -19. */
  | Algorithm
  /** A `typ` not its kind's. */
  | Typ
  /** A `kid` of no certificate given and not the root's. */
  | Unknown
  /** A signature its signer's key does not verify. */
  | Signature
  /** A signer whose role may not sign it. */
  | Role
  /** A signer holding a scope that what it signed does not hold. */
  | Scope
  /** Its `exp` reached. */
  | Expired
  /** Its `iat` more than 60 seconds ahead. */
  | Early
  /** A certificate above it refused, for this. */
  | Above(refused)

/** A record verified: its content, as its payload holds it, and who signed it. */
type verified = {content: Codec.Cbor.value, signer: signer}

/** The record verified as its kind, against what is trusted. */
let verify: (trust, kind, Uint8Array.t) => result<verified, refused>
