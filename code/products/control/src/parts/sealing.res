/***
 * A secret the control keeps, sealed by AES-256-GCM under the key in its `SEALING_KEY`, RFCs fhg6w
 * and b8f35, bound to the record and field it is kept in.
 */

/** The version a sealed secret begins with, then its nonce, then its ciphertext and tag. */
let version = 1
let nonceLength = 12
let tagLength = 16

/** The key the control was given, or why it keeps no secret. */
type t = Keyed(promise<Web.cryptoKey>) | Unkeyed(string)

let missing = "the control is given no SEALING_KEY, so it keeps and reads no secret"

/** The key in a Worker's `SEALING_KEY`, 32 bytes in unpadded base64url. */
let ofKey = (given: option<string>) =>
  switch given->Option.filter(text => text != "") {
  | None => Unkeyed(missing)
  | Some(text) =>
    switch Envelope.Base64url.decode(text) {
    | Some(bytes) if bytes->TypedArray.length == 32 => Keyed(Web.aesKey(bytes))
    | Some(_) | None => Unkeyed("the control's SEALING_KEY is not 32 bytes in base64url")
    }
  }

/** Where a secret is kept, `organization:1:secret`, what its seal is bound to. */
let place = (~kind, ~id, ~field) => Web.utf8(`${kind}:${Float.toString(id)}:${field}`)

/** A secret read, opened from its seal, or plain as it was kept before sealing and so to be sealed. */
type read = Opened(Uint8Array.t) | Plain(Uint8Array.t)

let keyOf = sealing =>
  switch sealing {
  | Keyed(key) => key
  | Unkeyed(why) => JsError.throwWithMessage(why)
  }

/** A secret sealed for its place, as hex. */
let seal = async (sealing, ~kind, ~id, ~field, secret) => {
  let key = await keyOf(sealing)
  let iv = Web.random(nonceLength)
  let sealed = await Web.sealed(key, ~iv, ~additionalData=place(~kind, ~id, ~field), secret)
  let byte = (bytes, i) => bytes->TypedArray.get(i)->Option.getOr(0)
  let written = Array.fromInitializer(~length=1 + nonceLength + sealed->TypedArray.length, i =>
    i == 0 ? version : i <= nonceLength ? byte(iv, i - 1) : byte(sealed, i - 1 - nonceLength)
  )
  Envelope.Hex.encode(Uint8Array.fromArray(written))
}

/** A secret kept as hex read for its place, a seal that does not open thrown and never taken as plain. */
let read = async (sealing, ~kind, ~id, ~field, text) => {
  let key = await keyOf(sealing)
  let at = `${kind}:${Float.toString(id)}:${field}`
  switch Envelope.Hex.decode(text) {
  | Some(bytes) if bytes->TypedArray.length == 32 => Plain(bytes)
  | Some(bytes)
    if bytes->TypedArray.get(0) == Some(version) &&
      bytes->TypedArray.length > 1 + nonceLength + tagLength =>
    let iv = bytes->TypedArray.slice(~start=1, ~end=1 + nonceLength)
    let sealed = bytes->TypedArray.slice(~start=1 + nonceLength)
    switch await Web.opened(key, ~iv, ~additionalData=place(~kind, ~id, ~field), sealed) {
    | Some(secret) => Opened(secret)
    | None => JsError.throwWithMessage(`the secret kept at ${at} does not open under this key`)
    }
  | Some(_) | None =>
    JsError.throwWithMessage(`the secret kept at ${at} is neither sealed nor plain`)
  }
}
