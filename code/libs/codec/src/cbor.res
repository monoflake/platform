/***
 * CBOR, RFC 8949, written as its 4.2.1 writes it and read strictly, as `src/cbor.rs` does over
 * minicbor, `docs/code.md`.
 */

type rec value =
  | Integer(bigint)
  | Bytes(Uint8Array.t)
  | Text(string)
  | Array(array<value>)
  | Map(array<(value, value)>)
  | Tag(bigint, value)
  | Bool(bool)
  | Null
  | Undefined
  | Simple(int)
  | Float(float)

type refused =
  | Truncated
  | Trailing
  | Syntax
  | Invalid
  | TooDeep
  | Nondeterministic

type unwritable =
  | OutOfRange
  | RepeatedKey
  | TooDeep

let depth = 128

/** The largest argument a head carries, 2^64 - 1. */
let largest = 18446744073709551615n

exception Unwritable(unwritable)

exception Refuse(refused)

let length = bytes => bytes->TypedArray.length

/** Bytes laid end to end. */
let concat = (parts: array<Uint8Array.t>) => {
  let joined = Uint8Array.fromLength(parts->Array.reduce(0, (n, part) => n + length(part)))
  let _ = parts->Array.reduce(0, (at, part) => {
    joined->Web.setFrom(part, at)
    at + length(part)
  })
  joined
}

/** Bytes in their bytewise order, a shorter one first where it begins the longer. */
let compareBytes = (a, b) => {
  let n = Math.Int.min(length(a), length(b))
  let rec from = i =>
    if i == n {
      Int.compare(length(a), length(b))
    } else {
      switch (a->TypedArray.get(i), b->TypedArray.get(i)) {
      | (Some(x), Some(y)) if x != y => Int.compare(x, y)
      | _ => from(i + 1)
      }
    }
  from(0)
}

let sameBytes = (a, b) => compareBytes(a, b) == 0.

/** `n` as `width` bytes, big-endian. */
let bigEndian = (n: bigint, width) =>
  Array.fromInitializer(~length=width, i =>
    BigInt.toInt(BigInt.bitwiseAnd(BigInt.shiftRight(n, BigInt.fromInt(8 * (width - 1 - i))), 255n))
  )

/** A head of `major` type carrying `argument`, in its shortest form, its 4.2.1's first rule. */
let head = (major, argument: bigint) => {
  if argument < 0n || argument > largest {
    throw(Unwritable(OutOfRange))
  }
  let initial = major * 32
  let bytes = if argument < 24n {
    [initial + BigInt.toInt(argument)]
  } else if argument < 256n {
    [initial + 24, ...bigEndian(argument, 1)]
  } else if argument < 65536n {
    [initial + 25, ...bigEndian(argument, 2)]
  } else if argument < 4294967296n {
    [initial + 26, ...bigEndian(argument, 4)]
  } else {
    [initial + 27, ...bigEndian(argument, 8)]
  }
  Uint8Array.fromArray(bytes)
}

let lengthHead = (major, n) => head(major, BigInt.fromInt(n))

/** A double's bits, and the double bits denote, by a `DataView`'s big-endian default. */
let bitsOf = x => {
  let view = DataView.fromBuffer(ArrayBuffer.make(8))
  view->DataView.setFloat64(0, x)
  view->DataView.getBigUint64(0)
}

/** A width narrower than a double's, by its exponent's bits and its fraction's. */
type width = {exponent: int, fraction: int}
let half = {exponent: 5, fraction: 10}
let single = {exponent: 8, fraction: 23}

let mask = bits => BigInt.sub(BigInt.shiftLeft(1n, BigInt.fromInt(bits)), 1n)
let lowZero = (n, bits) => BigInt.bitwiseAnd(n, mask(bits)) == 0n

/** The bits of the double `bits` at `width`, where that width holds it exactly; never a NaN. */
let narrow = (bits: bigint, width) => {
  let shl = (n, by) => BigInt.shiftLeft(n, BigInt.fromInt(by))
  let shr = (n, by) => BigInt.shiftRight(n, BigInt.fromInt(by))
  let sign = shl(shr(bits, 63), width.exponent + width.fraction)
  let biased = BigInt.toInt(BigInt.bitwiseAnd(shr(bits, 52), 2047n))
  let fraction = BigInt.bitwiseAnd(bits, mask(52))
  let ones = (1 << width.exponent) - 1
  if biased == 2047 {
    fraction == 0n ? Some(BigInt.bitwiseOr(sign, shl(BigInt.fromInt(ones), width.fraction))) : None
  } else if biased == 0 {
    // Zero, or a double's subnormal, which no narrower width reaches.
    fraction == 0n ? Some(sign) : None
  } else {
    let bias = ones / 2
    let exponent = biased - 1023
    let dropped = 52 - width.fraction
    if exponent > bias {
      None
    } else if exponent > -bias {
      lowZero(fraction, dropped)
        ? Some(
            BigInt.bitwiseOr(
              BigInt.bitwiseOr(sign, shl(BigInt.fromInt(exponent + bias), width.fraction)),
              shr(fraction, dropped),
            ),
          )
        : None
    } else {
      // A subnormal at `width`, the significand with its leading one shifted to its scale.
      let significand = BigInt.bitwiseOr(fraction, shl(1n, 52))
      let shift = dropped + 1 - bias - exponent
      shift <= 52 && lowZero(significand, shift)
        ? Some(BigInt.bitwiseOr(sign, shr(significand, shift)))
        : None
    }
  }
}

/** `x` at the narrowest width that holds it exactly, every NaN as f97e00. */
let floatBytes = x =>
  if Float.isNaN(x) {
    Uint8Array.fromArray([0xf9, 0x7e, 0x00])
  } else {
    let bits = bitsOf(x)
    switch (narrow(bits, half), narrow(bits, single)) {
    | (Some(h), _) => Uint8Array.fromArray([0xf9, ...bigEndian(h, 2)])
    | (None, Some(s)) => Uint8Array.fromArray([0xfa, ...bigEndian(s, 4)])
    | (None, None) => Uint8Array.fromArray([0xfb, ...bigEndian(bits, 8)])
    }
  }

/**
 * Whether a string is Unicode scalar values alone, with no lone surrogate, as UTF-8 can write it.
 */
let scalar = text => {
  let n = String.length(text)
  // Within the string, so always a code unit.
  let codeAt = i => text->String.charCodeAt(i)->Option.getOr(0)
  let isHigh = c => c >= 0xd800 && c <= 0xdbff
  let isLow = c => c >= 0xdc00 && c <= 0xdfff
  let rec from = i =>
    if i >= n {
      true
    } else if isHigh(codeAt(i)) {
      i + 1 < n && isLow(codeAt(i + 1)) && from(i + 2)
    } else {
      !isLow(codeAt(i)) && from(i + 1)
    }
  from(0)
}

/** `value` within `within` arrays, maps and tags, as 4.2.1 writes it. */
let rec write = (value, within): array<Uint8Array.t> => {
  if within > depth {
    throw(Unwritable(TooDeep))
  }
  let inner = within + 1
  switch value {
  | Integer(n) => n < 0n ? [head(1, BigInt.sub(-1n, n))] : [head(0, n)]
  | Bytes(bytes) => [lengthHead(2, length(bytes)), bytes]
  | Text(text) =>
    if !scalar(text) {
      throw(Unwritable(OutOfRange))
    }
    let bytes = Web.utf8(text)
    [lengthHead(3, length(bytes)), bytes]
  | Array(items) => [lengthHead(4, items->Array.length), ...items->Array.flatMap(write(_, inner))]
  | Map(pairs) =>
    // Each key is written alone first, so the pairs are put in the bytewise order of their keys'
    // encodings, where two keys written alike stand side by side.
    let written =
      pairs
      ->Array.map(((key, value)) => (concat(write(key, inner)), concat(write(value, inner))))
      ->Array.toSorted(((a, _), (b, _)) => compareBytes(a, b))
    let repeated = written->Array.someWithIndex(((key, _), i) =>
      switch written->Array.get(i - 1) {
      | Some((before, _)) => sameBytes(before, key)
      | None => false
      }
    )
    if repeated {
      throw(Unwritable(RepeatedKey))
    }
    [lengthHead(5, pairs->Array.length), ...written->Array.flatMap(((k, v)) => [k, v])]
  | Tag(tag, content) => [head(6, tag), ...write(content, inner)]
  | Bool(false) => [Uint8Array.fromArray([0xf4])]
  | Bool(true) => [Uint8Array.fromArray([0xf5])]
  | Null => [Uint8Array.fromArray([0xf6])]
  | Undefined => [Uint8Array.fromArray([0xf7])]
  | Simple(n) if n >= 0 && n <= 19 => [Uint8Array.fromArray([0xe0 + n])]
  | Simple(n) if n >= 32 && n <= 255 => [Uint8Array.fromArray([0xf8, n])]
  // 20 to 23 are false, true, null and undefined, and 24 to 31 reserved, its 3.3.
  | Simple(_) => throw(Unwritable(OutOfRange))
  | Float(x) => [floatBytes(x)]
  }
}

let encode = value =>
  try Ok(concat(write(value, 0))) catch {
  | Unwritable(why) => Error(why)
  }

type reader = {
  bytes: Uint8Array.t,
  mutable at: int,
  /** Whether an item read so far was well formed yet not valid. */
  mutable invalid: bool,
}

/** The byte the next head begins with, looked at and not taken. */
let first = r =>
  switch r.bytes->TypedArray.get(r.at) {
  | Some(b) => b
  | None => throw(Refuse(Truncated))
  }

let byte = r => {
  let b = first(r)
  r.at = r.at + 1
  b
}

/** Whether a break comes next, taken if it does. */
let ended = r => {
  let ended = first(r) == 0xff
  if ended {
    r.at = r.at + 1
  }
  ended
}

let take = (r, n: bigint) => {
  if n > BigInt.fromInt(length(r.bytes) - r.at) {
    throw(Refuse(Truncated))
  }
  let end = r.at + BigInt.toInt(n)
  let taken = r.bytes->TypedArray.slice(~start=r.at, ~end)
  r.at = end
  taken
}

/** `width` bytes as the unsigned integer they spell, big-endian. */
let uint = (r, width) =>
  take(r, BigInt.fromInt(width))->TypedArray.reduce(
    (n, b) => BigInt.add(BigInt.mul(n, 256n), BigInt.fromInt(b)),
    0n,
  )

/** A head's argument taken with the head, additional information 28 to 31 giving none. */
let argument = r => {
  let info = byte(r) &&& 0x1f
  switch info {
  | 24 => uint(r, 1)
  | 25 => uint(r, 2)
  | 26 => uint(r, 4)
  | 27 => uint(r, 8)
  | info if info < 24 => BigInt.fromInt(info)
  | _ => throw(Refuse(Syntax))
  }
}

/** A view of `width` bytes to read a float from. */
let viewOf = (r, width) => DataView.fromBuffer(take(r, BigInt.fromInt(width))->TypedArray.buffer)

/**
 * The double a half's bits denote, a subnormal scaled and anything else widened to a single's bits.
 */
let fromHalf = bits => {
  let sign = bits >> 15 == 1 ? -1. : 1.
  let exponent = bits >> 10 &&& 0x1f
  let fraction = bits &&& 0x3ff
  if exponent == 0 {
    sign *. Int.toFloat(fraction) /. 16777216.
  } else {
    let view = DataView.fromBuffer(ArrayBuffer.make(4))
    let widened = exponent == 0x1f ? 0xff : exponent + 112
    view->DataView.setUint32(0, bits >> 15 << 31 ||| widened << 23 ||| fraction << 13)
    view->DataView.getFloat32(0)
  }
}

/** A map's keys each apart from the others, as their encodings are, its 5.6. */
let checkKeys = (r, pairs) => {
  let seen = Set.make()
  pairs->Array.forEach(((key, _)) =>
    switch encode(key) {
    | Ok(bytes) =>
      let spelled = bytes->TypedArray.toString
      if seen->Set.has(spelled) {
        r.invalid = true
      }
      seen->Set.add(spelled)
    // A key read well formed is always written; one that is not would be refused anyway.
    | Error(OutOfRange | RepeatedKey | TooDeep) => r.invalid = true
    }
  )
}

/** `n` of what `next` reads, in order. */
let definite = (n, next) => {
  let items = []
  let i = ref(0n)
  while i.contents < n {
    items->Array.push(next())
    i := BigInt.add(i.contents, 1n)
  }
  items
}

/** What `next` reads, up to a break. */
let indefinite = (r, next) => {
  let items = []
  while !ended(r) {
    items->Array.push(next())
  }
  items
}

/** An array's or a map's items, of a definite count or up to a break. */
let items = (r, next) =>
  if (first(r) &&& 0x1f) == 31 {
    r.at = r.at + 1
    indefinite(r, next)
  } else {
    definite(argument(r), next)
  }

/**
 * A string's bytes of `major` type 2 or 3, one definite string or its chunks up to a break, its
 * 3.2.3.
 */
let chunks = (r, major) =>
  if (first(r) &&& 0x1f) == 31 {
    r.at = r.at + 1
    indefinite(r, () => {
      let initial = first(r)
      if initial >> 5 != major || (initial &&& 0x1f) == 31 {
        throw(Refuse(Syntax))
      }
      take(r, argument(r))
    })
  } else {
    [take(r, argument(r))]
  }

/** A text's chunk, which is not valid where it is not UTF-8, its 5.3.1, and reading goes on. */
let utf8 = (r, chunk) =>
  switch Web.fromUtf8(chunk) {
  | Some(text) => text
  | None =>
    r.invalid = true
    ""
  }

/** What major type 7 holds, a simple value or a float, a break being out of place here. */
let simple = r =>
  switch byte(r) {
  | 0xf4 => Bool(false)
  | 0xf5 => Bool(true)
  | 0xf6 => Null
  | 0xf7 => Undefined
  | 0xf8 =>
    switch byte(r) {
    | n if n < 32 => throw(Refuse(Syntax))
    | n => Simple(n)
    }
  | 0xf9 => Float(fromHalf(BigInt.toInt(uint(r, 2))))
  | 0xfa => Float(viewOf(r, 4)->DataView.getFloat32(0))
  | 0xfb => Float(viewOf(r, 8)->DataView.getFloat64(0))
  | initial if initial < 0xf4 => Simple(initial - 0xe0)
  // fc to fe are reserved, and ff a break out of place.
  | _ => throw(Refuse(Syntax))
  }

/** One item within `within` arrays, maps and tags, where a break is out of place. */
let rec item = (r, within) => {
  if within > depth {
    throw(Refuse(TooDeep))
  }
  let inner = within + 1
  switch first(r) >> 5 {
  | 0 => Integer(argument(r))
  | 1 => Integer(BigInt.sub(-1n, argument(r)))
  | 2 => Bytes(concat(chunks(r, 2)))
  | 3 => Text(chunks(r, 3)->Array.map(utf8(r, _))->Array.join(""))
  | 4 => Array(items(r, () => item(r, inner)))
  | 5 =>
    let pairs = items(r, () => {
      let key = item(r, inner)
      (key, item(r, inner))
    })
    checkKeys(r, pairs)
    Map(pairs)
  | 6 =>
    let tag = argument(r)
    Tag(tag, item(r, inner))
  // Major type 7, the last of three bits.
  | _ => simple(r)
  }
}

let decode = bytes => {
  let r = {bytes, at: 0, invalid: false}
  try {
    let value = item(r, 0)
    if r.at < length(bytes) {
      Error(Trailing)
    } else if r.invalid {
      Error(Invalid)
    } else {
      Ok(value)
    }
  } catch {
  | Refuse(refused) => Error(refused)
  }
}

let decodeDeterministic = bytes =>
  switch decode(bytes) {
  | Ok(value) =>
    // A value read is always written, so what is written differs from what was read exactly where
    // what was read is not as 4.2.1 writes it.
    switch encode(value) {
    | Ok(written) if sameBytes(written, bytes) => Ok(value)
    | Ok(_) | Error(OutOfRange | RepeatedKey | TooDeep) => Error(Nondeterministic)
    }
  | Error(refused) => Error(refused)
  }
