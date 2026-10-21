/*** A CWT, RFC 8392, a claims set carried as a Sign1's payload, as `src/cwt.rs` is in Rust. */

type claims = array<(Cbor.value, Cbor.value)>

type refused =
  | Sign1(Sign1.refused)
  | Detached
  | Payload(Cbor.refused)
  | Unclaimed

/** CWT's tag, RFC 8392's 6, which stands outside the COSE message's own. */
let tag = 61n

/** COSE_Sign1's own tag, RFC 9052's 2. */
let sign1Tag = 18n

let payload = claims => Cbor.encode(Map(claims))

/** The bytes after the head of the tag `bytes` begins with, by its additional information. */
let afterTag = bytes => {
  let info = bytes->TypedArray.get(0)->Option.getOr(0) &&& 0x1f
  let head = info < 24 ? 1 : 1 + (1 << info - 24)
  bytes->TypedArray.subarray(~start=head, ~end=TypedArray.length(bytes))
}

/** The Sign1 `bytes` hold, under tags 61 and 18, 18 alone, or neither. */
let sign1 = bytes =>
  switch Cbor.decode(bytes) {
  | Error(refused) => Error(Sign1.Cbor(refused))
  | Ok(Tag(outer, inner)) if outer == tag =>
    switch inner {
    | Tag(t, _) if t == sign1Tag => Sign1.decode(afterTag(bytes))
    // Under tag 61 the Sign1 stands under its own tag 18 as well.
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
    | Float(_) =>
      Error(Sign1.Shape)
    }
  | Ok(
      Tag(_)
      | Integer(_)
      | Bytes(_)
      | Text(_)
      | Array(_)
      | Map(_)
      | Bool(_)
      | Null
      | Undefined
      | Simple(_)
      | Float(_),
    ) =>
    Sign1.decode(bytes)
  }

let decode = bytes =>
  switch sign1(bytes) {
  | Error(refused) => Error(Sign1(refused))
  | Ok(({payload: None}, _)) => Error(Detached)
  | Ok(({payload: Some(payload)} as read, _)) =>
    switch Cbor.decode(payload) {
    | Ok(Map(claims)) => Ok((read, claims))
    | Ok(
        Integer(_)
        | Bytes(_)
        | Text(_)
        | Array(_)
        | Tag(_)
        | Bool(_)
        | Null
        | Undefined
        | Simple(_)
        | Float(_),
      ) =>
      Error(Unclaimed)
    | Error(refused) => Error(Payload(refused))
    }
  }
