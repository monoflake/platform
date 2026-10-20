/***
 * COSE's Sign1, RFC 9052's 4.2, its structure alone. `src/sign1.rs` is the same in Rust.
 */

type t = {
  protected: Uint8Array.t,
  unprotected: array<(Cbor.value, Cbor.value)>,
  payload: option<Uint8Array.t>,
  signature: Uint8Array.t,
}

type refused =
  | Cbor(Cbor.refused)
  | Shape

/** COSE_Sign1's tag, RFC 9052's 2. */
let tag = 18n

/** Whether bytes are h'a0', an empty map serialized, which RFC 9052's 3 takes as no bytes. */
let isEmptyMap = bytes => TypedArray.length(bytes) == 1 && bytes->TypedArray.get(0) == Some(0xa0)

let toBeSigned = (~protected, ~aad, ~payload) => {
  let protected = isEmptyMap(protected) ? Uint8Array.fromLength(0) : protected
  switch Cbor.encode(Array([Text("Signature1"), Bytes(protected), Bytes(aad), Bytes(payload)])) {
  | Ok(bytes) => bytes
  // Byte strings and a text under an array of four are always written.
  | Error(OutOfRange | RepeatedKey | TooDeep) => Uint8Array.fromLength(0)
  }
}

let encode = (sign1, ~tagged) => {
  let fields = Cbor.Array([
    Bytes(sign1.protected),
    Map(sign1.unprotected),
    sign1.payload->Option.mapOr(Cbor.Null, payload => Bytes(payload)),
    Bytes(sign1.signature),
  ])
  Cbor.encode(tagged ? Tag(tag, fields) : fields)
}

/** A byte string's bytes, or none where `value` is anything else. */
let bytesOf = (value: Cbor.value) =>
  switch value {
  | Bytes(bytes) => Some(bytes)
  | Integer(_)
  | Text(_)
  | Array(_)
  | Map(_)
  | Tag(_)
  | Bool(_)
  | Null
  | Undefined
  | Simple(_)
  | Float(_) =>
    None
  }

/** A map's pairs, or none where `value` is anything else. */
let mapOf = (value: Cbor.value) =>
  switch value {
  | Map(pairs) => Some(pairs)
  | Integer(_)
  | Bytes(_)
  | Text(_)
  | Array(_)
  | Tag(_)
  | Bool(_)
  | Null
  | Undefined
  | Simple(_)
  | Float(_) =>
    None
  }

/** A payload, its bytes or nil where it is detached, or none where `value` is anything else. */
let payloadOf = (value: Cbor.value) =>
  switch value {
  | Bytes(bytes) => Some(Some(bytes))
  | Null => Some(None)
  | Integer(_)
  | Text(_)
  | Array(_)
  | Map(_)
  | Tag(_)
  | Bool(_)
  | Undefined
  | Simple(_)
  | Float(_) =>
    None
  }

/** The four fields, each of its type. */
let fieldsOf = (fields: Cbor.value) =>
  switch fields {
  | Array([protected, unprotected, payload, signature]) =>
    switch (bytesOf(protected), mapOf(unprotected), payloadOf(payload), bytesOf(signature)) {
    | (Some(protected), Some(unprotected), Some(payload), Some(signature)) =>
      Ok({protected, unprotected, payload, signature})
    | (None, _, _, _) | (_, None, _, _) | (_, _, None, _) | (_, _, _, None) => Error(Shape)
    }
  | Array(_)
  | Integer(_)
  | Bytes(_)
  | Text(_)
  | Map(_)
  | Tag(_)
  | Bool(_)
  | Null
  | Undefined
  | Simple(_)
  | Float(_) =>
    Error(Shape)
  }

/**
 * The four fields of an untagged Sign1, its protected bytes kept as written; a tag here is another
 * message's, not a Sign1.
 */
let shape = fields =>
  fieldsOf(fields)->Result.flatMap(sign1 =>
    TypedArray.length(sign1.protected) == 0 ||
      Cbor.decode(sign1.protected)->Result.mapOr(false, map => mapOf(map)->Option.isSome)
      ? Ok(sign1)
      : Error(Shape)
  )

/** The item a Sign1 stands as, and whether it stood under tag 18. */
let untag = (item: Cbor.value) =>
  switch item {
  | Tag(t, fields) if t == tag => (fields, true)
  | Tag(_)
  | Integer(_)
  | Bytes(_)
  | Text(_)
  | Array(_)
  | Map(_)
  | Bool(_)
  | Null
  | Undefined
  | Simple(_)
  | Float(_) => (item, false)
  }

let decode = bytes =>
  switch Cbor.decode(bytes) {
  | Ok(item) =>
    let (fields, tagged) = untag(item)
    shape(fields)->Result.map(sign1 => (sign1, tagged))
  | Error(refused) => Error(Cbor(refused))
  }
