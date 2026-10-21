/***
 * Every signed record verified, a COSE Sign1 by Ed25519 to the root, as `docs/signed.md` lays out,
 * RFC b8f35. Nothing here reads a clock. The model's interface, `docs/code.md`.
 */

/** What a signed record is, each by its `typ`. */
type kind =
  /** `monoflake:capability:3`. */
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

/**
 * What a record is verified against, the root's 32-byte public key, the certificates known as
 * signed, and the time in seconds.
 */
type trust = {root: Uint8Array.t, certificates: array<Uint8Array.t>, now: float}

/** Who signed, the root or a certificate's role, its scope where it holds one, and its `sub`. */
type signer =
  | Root
  | Signed({role: string, scope: option<float>, sub: option<string>})

/** Why a record is refused, the first of these as it is read, then its signer's, then above. */
type rec refused =
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

/** A record verified, its content as its payload holds it, and who signed it. */
type verified = {content: Codec.Cbor.value, signer: signer}

/** The record verified as its kind, against what is trusted. */
let verify: (trust, kind, Uint8Array.t) => result<verified, refused>
