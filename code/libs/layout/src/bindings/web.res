/***
 * What layout takes of the web's APIs beyond ReScript's Stdlib, a typed array's `set` and
 * WebCrypto's AES-256-GCM.
 */

/** Writes `source` into `target` from `offset`. */
@send external setFrom: (Uint8Array.t, Uint8Array.t, int) => unit = "set"

type cryptoKey
type algorithm = {name: string}
type gcm = {name: string, iv: Uint8Array.t, additionalData: Uint8Array.t}

@val @scope(("crypto", "subtle"))
external importKey: (
  @as("raw") _,
  Uint8Array.t,
  algorithm,
  @as(json`false`) _,
  array<string>,
) => promise<cryptoKey> = "importKey"
@val @scope(("crypto", "subtle"))
external encrypt: (gcm, cryptoKey, Uint8Array.t) => promise<ArrayBuffer.t> = "encrypt"
@val @scope(("crypto", "subtle"))
external decrypt: (gcm, cryptoKey, Uint8Array.t) => promise<ArrayBuffer.t> = "decrypt"

/** A key of 32 bytes, for AES-256-GCM, to seal and open with and never exported. */
let key = bytes => importKey(bytes, {name: "AES-GCM"}, ["encrypt", "decrypt"])

/** The bytes sealed under the nonce and the associated data, their tag after them. */
let sealed = async (key, ~iv, ~additionalData, bytes) =>
  Uint8Array.fromBuffer(await encrypt({name: "AES-GCM", iv, additionalData}, key, bytes))

/** The bytes a ciphertext sealed, or none where its tag does not hold. */
let opened = async (key, ~iv, ~additionalData, bytes) =>
  try Some(
    Uint8Array.fromBuffer(await decrypt({name: "AES-GCM", iv, additionalData}, key, bytes)),
  ) catch {
  | JsExn(_) => None
  }
