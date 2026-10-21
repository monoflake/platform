/***
 * Every context the platform derives under, RFC b8f35, the one list of them: each
 * `monoflake:{scope}:{type}:{version}`, written into the code and never changed, its words whole,
 * of lowercase letters and digits, its version raised by a change to what is derived, RFC wnqvu.
 * The model's interface, `docs/code.md`.
 */

type t =
  /** `monoflake:organization:salt:1`: a scope's salt, at version 1 forever, since another would
   * change every hash. */
  | Salt
  /** `monoflake:organization:key:1`: a scope's key, from the encryption master of a version. */
  | Key
  /** `monoflake:journal:key:1`: a journal's key, from its scope's key and its seed. */
  | Journal
  /** `monoflake:parcel:key:1`: a parcel's key, from its scope's key and its seed. */
  | Parcel
  /** `monoflake:organization:gear:1`: FastCDC's gear table, from a scope's salt. */
  | Gear
  /** `monoflake:parcel:placement:1`: a store's score for a parcel, by rendezvous. */
  | Placement

/** Every context, in the order above. */
let all: array<t>

/** The context's text, as BLAKE3's `derive_key` takes it. */
let text: t => string
