/***
 * `Cbor` held to RFC 8949's own examples in `tests/cbor/`, read as they stand, and to what they
 * leave out: what 4.2.1 writes, what is refused, and in which order. `cbor.rs` beside it is the
 * same in Rust.
 */
open Node
open Sample

let wellFormed = "tests/cbor/well-formed.json"
let notWellFormed = "tests/cbor/not-well-formed.json"
let sortedKeys = "tests/cbor/sorted-keys.json"

let encoded = value =>
  switch Cbor.encode(value) {
  | Ok(bytes) => bytes
  | Error(OutOfRange | RepeatedKey | TooDeep) => JsError.throwWithMessage("unwritable")
  }

let decoded = bytes =>
  switch Cbor.decode(bytes) {
  | Ok(value) => value
  | Error(_) => JsError.throwWithMessage(`${bytes->TypedArray.toString}: refused`)
  }

test("appendix A is read and its deterministic items written back byte for byte", () =>
  items(wellFormed)->Array.forEach(item => {
    let message = item->at(["hex"])->string
    let bytes = item->hexAt(["hex"])
    let value = Cbor.decode(bytes)
    ok(value->Result.isOk, ~message)
    switch item->at(["deterministic"])->JSON.Decode.bool {
    | Some(true) =>
      ok(Cbor.decodeDeterministic(bytes)->Result.isOk, ~message)
      deepEqual(encoded(decoded(bytes)), bytes, ~message)
    | Some(false) => deepEqual(Cbor.decodeDeterministic(bytes), Error(Nondeterministic), ~message)
    | None => JsError.throwWithMessage(`${message}: no deterministic`)
    }
  })
)

/**
 * The refusal each of Appendix F.1's kinds implies: the first five are its "too little data", the
 * rest its syntax errors.
 */
let refusal = (kind): Cbor.refused =>
  switch kind {
  | "end of input in a head"
  | "definite-length strings with short data"
  | "definite-length maps and arrays not closed with enough items"
  | "tag number not followed by tag content"
  | "indefinite-length strings not closed by a \"break\" stop code"
  | "indefinite-length maps and arrays not closed by a \"break\" stop code" =>
    Truncated
  | "reserved additional information values"
  | "reserved two-byte encodings of simple values"
  | "indefinite-length string chunks not of the correct type"
  | "indefinite-length string chunks not definite length"
  | "break occurring on its own outside of an indefinite-length item"
  | "break occurring in a definite-length array or map or a tag"
  | "break in an indefinite-length map that would lead to an odd number of items (break in a value position)"
  | "major type 0, 1, 6 with additional information 31" =>
    Syntax
  | _ => JsError.throwWithMessage(`${kind}: a kind of Appendix F.1 this test does not know`)
  }

test("appendix F is refused each by its kind", () =>
  items(notWellFormed)->Array.forEach(item => {
    let message = item->at(["hex"])->string
    let bytes = item->hexAt(["hex"])
    let expected = Error(refusal(item->at(["kind"])->string))
    deepEqual(Cbor.decode(bytes), expected, ~message)
    deepEqual(Cbor.decodeDeterministic(bytes), expected, ~message)
  })
)

test("a map is written in the bytewise order of its keys however it was given", () => {
  let keys = items(sortedKeys)->Array.map(key => key->hexAt(["hex"]))
  let expected = bytes(
    [0xa0 + keys->Array.length, ...keys->Array.flatMap(key => [...ints(key), 0xf6])],
  )
  let given = keys->Array.map(decoded)->Array.toReversed
  for shift in 0 to given->Array.length - 1 {
    let rotated = Array.concat(
      given->Array.slice(~start=shift),
      given->Array.slice(~start=0, ~end=shift),
    )
    deepEqual(encoded(Map(rotated->Array.map(key => (key, Cbor.Null)))), expected)
  }
  deepEqual(encoded(decoded(expected)), expected)
})

test("a map keeps its pairs in the order read", () => {
  let read = decoded(bytes([0xa2, 0x02, 0x00, 0x01, 0x00]))
  deepEqual(read, Map([(Integer(2n), Integer(0n)), (Integer(1n), Integer(0n))]))
  deepEqual(encoded(read), bytes([0xa2, 0x01, 0x00, 0x02, 0x00]))
  deepEqual(
    Cbor.decodeDeterministic(bytes([0xa2, 0x02, 0x00, 0x01, 0x00])),
    Error(Nondeterministic),
  )
})

test("integers and floats are kept apart", () => {
  deepEqual(Cbor.decode(bytes([0x01])), Ok(Integer(1n)))
  deepEqual(Cbor.decode(bytes([0xf9, 0x3c, 0x00])), Ok(Float(1.)))
  deepEqual(encoded(Float(1.)), bytes([0xf9, 0x3c, 0x00]))
  deepEqual(encoded(Integer(1n)), bytes([0x01]))
})

test("a float is written at the narrowest width that keeps it", () => {
  let cases = [
    (0., [0xf9, 0x00, 0x00]),
    (-0., [0xf9, 0x80, 0x00]),
    (65504., [0xf9, 0x7b, 0xff]),
    (65505., [0xfa, 0x47, 0x7f, 0xe1, 0x00]),
    // 2^-127, a single's subnormal; 2^-149, its least; 2^-150, which no single holds.
    (5.877471754111438e-39, [0xfa, 0x00, 0x40, 0x00, 0x00]),
    (1.401298464324817e-45, [0xfa, 0x00, 0x00, 0x00, 0x01]),
    (7.006492321624085e-46, [0xfb, 0x36, 0x90, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
    (5e-324, [0xfb, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01]),
    // A half's subnormals: 2^-24 and 3 * 2^-16.
    (5.960464477539063e-8, [0xf9, 0x00, 0x01]),
    (0.0000457763671875, [0xf9, 0x03, 0x00]),
    (Float.Constants.nan, [0xf9, 0x7e, 0x00]),
  ]
  cases->Array.forEach(((x, written)) => {
    let message = Float.toString(x)
    deepEqual(encoded(Float(x)), bytes(written), ~message)
    deepEqual(Cbor.decode(bytes(written)), Ok(Float(x)), ~message)
  })
  // A NaN but f97e00 is read, and refused as written longer than it need be.
  deepEqual(Cbor.decode(bytes([0xf9, 0x7e, 0x01])), Ok(Float(Float.Constants.nan)))
  deepEqual(Cbor.decodeDeterministic(bytes([0xf9, 0x7e, 0x01])), Error(Nondeterministic))
})

test("what CBOR cannot write is out of range", () => {
  let least = -18446744073709551616n
  deepEqual(encoded(Integer(least)), bytes([0x3b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]))
  deepEqual(Cbor.encode(Integer(least - 1n)), Error(OutOfRange))
  deepEqual(Cbor.encode(Integer(18446744073709551616n)), Error(OutOfRange))
  for n in 20 to 31 {
    deepEqual(Cbor.encode(Simple(n)), Error(OutOfRange), ~message=Int.toString(n))
  }
  deepEqual(Cbor.encode(Simple(-1)), Error(OutOfRange))
  deepEqual(Cbor.encode(Simple(256)), Error(OutOfRange))
  deepEqual(encoded(Simple(19)), bytes([0xf3]))
  deepEqual(encoded(Simple(32)), bytes([0xf8, 0x20]))
  deepEqual(Cbor.encode(Tag(-1n, Null)), Error(OutOfRange))
  deepEqual(Cbor.encode(Tag(18446744073709551616n, Null)), Error(OutOfRange))
  deepEqual(Cbor.encode(Array([Map([(Simple(24), Null)])])), Error(OutOfRange))
  // A lone surrogate is no Unicode scalar value, so UTF-8 cannot write it.
  deepEqual(Cbor.encode(Text(String.fromCharCode(0xd800))), Error(OutOfRange))
  deepEqual(Cbor.encode(Text("a" ++ String.fromCharCode(0xdc00))), Error(OutOfRange))
  deepEqual(encoded(Text(String.fromCodePoint(0x10151))), bytes([0x64, 0xf0, 0x90, 0x85, 0x91]))
})

test("a map holding one key twice is never written", () => {
  let twice = key => Cbor.Map([(key, Null), (key, Integer(1n))])
  deepEqual(Cbor.encode(twice(Integer(1n))), Error(RepeatedKey))
  deepEqual(Cbor.encode(twice(Text("a"))), Error(RepeatedKey))
  // Two NaNs, 7ff8000000000001 the second, are both written f97e00, so are one key.
  let other = DataView.fromBuffer(ArrayBuffer.make(8))
  other->DataView.setBigUint64(0, 9221120237041090561n)
  let nans = Cbor.Map([
    (Float(Float.Constants.nan), Null),
    (Float(other->DataView.getFloat64(0)), Null),
  ])
  deepEqual(Cbor.encode(nans), Error(RepeatedKey))
  deepEqual(Cbor.encode(Array([twice(Null)])), Error(RepeatedKey))
  // Zero and its negative are two floats; an integer and a float are two keys.
  let apart = Cbor.Map([(Float(0.), Null), (Float(-0.), Null), (Integer(0n), Null)])
  deepEqual(
    encoded(apart),
    bytes([0xa3, 0x00, 0xf6, 0xf9, 0x00, 0x00, 0xf6, 0xf9, 0x80, 0x00, 0xf6]),
  )
})

/** `inner` within `n` arrays, maps and tags in turn, and its bytes: `[x]`, `{0: x}` and `0(x)`. */
let nested = (n, inner) => {
  let value = ref(inner)
  let written = ref(ints(encoded(inner)))
  for at in 0 to n - 1 {
    let (wrapped, head) = switch mod(at, 3) {
    | 0 => (Cbor.Array([value.contents]), [0x81])
    | 1 => (Cbor.Map([(Integer(0n), value.contents)]), [0xa1, 0x00])
    | _ => (Cbor.Tag(0n, value.contents), [0xc0])
    }
    value := wrapped
    written := Array.concat(head, written.contents)
  }
  (value.contents, bytes(written.contents))
}

test("an item within 128 arrays, maps and tags is read and written, and within 129 refused", () => {
  deepEqual(Cbor.depth, 128)
  [Cbor.Integer(0n), Array([]), Map([])]->Array.forEach(inner => {
    let (within, written) = nested(Cbor.depth, inner)
    deepEqual(encoded(within), written)
    deepEqual(Cbor.decodeDeterministic(written), Ok(within))
  })
  let (deeper, written) = nested(Cbor.depth + 1, Integer(0n))
  deepEqual(Cbor.encode(deeper), Error(TooDeep))
  deepEqual(Cbor.decode(written), Error(TooDeep))
  // A key is within its map as a value is.
  let (key, written) = nested(Cbor.depth, Integer(0n))
  deepEqual(Cbor.encode(Map([(key, Null)])), Error(TooDeep))
  deepEqual(Cbor.decode(bytes([0xa1, ...ints(written), 0xf6])), Error(TooDeep))
})

test("too deep is refused as soon as it is met", () => {
  let repeated = (byte, n) => Array.make(~length=n, byte)
  // Before the input ends, before bytes trail, and before what is not valid.
  deepEqual(Cbor.decode(bytes(repeated(0x81, 200))), Error(TooDeep))
  deepEqual(Cbor.decode(bytes([...repeated(0x81, 129), 0x00, 0x00])), Error(TooDeep))
  deepEqual(Cbor.decode(bytes([0x82, 0x61, 0xff, ...repeated(0x81, 129), 0x00])), Error(TooDeep))
  // Within 128, the input ending is what is refused.
  deepEqual(Cbor.decode(bytes(repeated(0x81, 128))), Error(Truncated))
  // The 129th indefinite array stands within 128, and holds nothing deeper.
  let indefinite = bytes([...repeated(0x9f, 129), ...repeated(0xff, 129)])
  ok(Cbor.decode(indefinite)->Result.isOk)
  deepEqual(Cbor.decodeDeterministic(indefinite), Error(Nondeterministic))
})

test("what is well formed yet not valid is invalid", () => {
  // A text not UTF-8, whole or split across two chunks each not UTF-8 alone.
  deepEqual(Cbor.decode(bytes([0x61, 0xff])), Error(Invalid))
  deepEqual(Cbor.decode(bytes([0x7f, 0x61, 0xc3, 0x61, 0xbc, 0xff])), Error(Invalid))
  deepEqual(
    Cbor.decode(bytes([0x7f, 0x62, 0xc3, 0xbc, 0xff])),
    Ok(Text(String.fromCodePoint(0xfc))),
  )
  // Reading goes on past a text not UTF-8, so what follows it is read as it stands.
  deepEqual(Cbor.decode(bytes([0x82, 0x61, 0xff, 0x00])), Error(Invalid))
  deepEqual(Cbor.decode(bytes([0x82, 0x61, 0xff, 0x00, 0x00])), Error(Trailing))
  deepEqual(Cbor.decode(bytes([0x82, 0x61, 0xff])), Error(Truncated))
  // A byte order mark is text, kept.
  deepEqual(Cbor.decode(bytes([0x63, 0xef, 0xbb, 0xbf])), Ok(Text(String.fromCodePoint(0xfeff))))
  // A key repeated, as written or as two encodings of one value.
  deepEqual(Cbor.decode(bytes([0xa2, 0x01, 0x00, 0x01, 0x00])), Error(Invalid))
  deepEqual(Cbor.decode(bytes([0xa2, 0x01, 0x00, 0x18, 0x01, 0x00])), Error(Invalid))
  // An integer and a float are no repeated key.
  ok(Cbor.decode(bytes([0xa2, 0x01, 0x00, 0xf9, 0x3c, 0x00, 0x00]))->Result.isOk)
})

test("not well formed and trailing come before invalid", () => {
  // A repeated key and then the end of input inside the array holding it.
  deepEqual(Cbor.decode(bytes([0x82, 0xa2, 0x01, 0x00, 0x01, 0x00])), Error(Truncated))
  deepEqual(Cbor.decode(bytes([0x82, 0xa2, 0x01, 0x00, 0x01, 0x00, 0x1c])), Error(Syntax))
  deepEqual(Cbor.decode(bytes([0xa2, 0x01, 0x00, 0x01, 0x00, 0x00])), Error(Trailing))
  deepEqual(Cbor.decode(bytes([0x00, 0x00])), Error(Trailing))
  deepEqual(Cbor.decode(bytes([])), Error(Truncated))
})

test("a head longer than it need be is refused only strictly", () => {
  [[0x18, 0x17], [0x19, 0x00, 0xff], [0x5f, 0xff], [0xd8, 0x01, 0x00]]->Array.forEach(written => {
    let message = written->Array.map(Int.toString(_, ~radix=16))->Array.join(" ")
    ok(Cbor.decode(bytes(written))->Result.isOk, ~message)
    deepEqual(Cbor.decodeDeterministic(bytes(written)), Error(Nondeterministic), ~message)
  })
  // A float written wider than it need be.
  deepEqual(
    Cbor.decodeDeterministic(bytes([0xfa, 0x3f, 0x80, 0x00, 0x00])),
    Error(Nondeterministic),
  )
})

test("tags and simple values are kept as written", () => {
  // A bignum is a tag of a byte string, whatever it holds.
  let bignum = bytes([0xc2, 0x43, 0x00, 0x00, 0x01])
  deepEqual(Cbor.decodeDeterministic(bignum), Ok(Tag(2n, Bytes(bytes([0, 0, 1])))))
  deepEqual(encoded(decoded(bignum)), bignum)
  deepEqual(Cbor.decode(bytes([0xf8, 0xff])), Ok(Simple(255)))
  deepEqual(Cbor.decode(bytes([0xe0])), Ok(Simple(0)))
  deepEqual(Cbor.decode(bytes([0xf8, 0x20])), Ok(Simple(32)))
})

test("a chunk of another type is refused by its first byte", () => {
  // Its head cut short, or whole, the chunk's type is already wrong.
  [[0x5f, 0x38], [0x5f, 0x3b, 0x00], [0x7f, 0x81], [0x5f, 0x7f]]->Array.forEach(written => {
    let message = written->Array.map(Int.toString(_, ~radix=16))->Array.join(" ")
    deepEqual(Cbor.decode(bytes(written)), Error(Syntax), ~message)
  })
  deepEqual(Cbor.decode(bytes([0x5f, 0x41])), Error(Truncated))
  deepEqual(Cbor.decode(bytes([0x5f, 0x5c])), Error(Syntax))
})
