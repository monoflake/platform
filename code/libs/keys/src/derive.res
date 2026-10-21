/***
 * What is derived from the masters and a scope, RFC b8f35, each BLAKE3's `derive_key` under its
 * context over its parts joined in order.
 */

type refused =
  | Length({part: string, length: int})
  | Range({part: string})

let derive = (context, material, ~length=32) =>
  Blake3.hashWith(material, {context: Web.utf8(Context.text(context)), dkLen: length})

/** Bytes that must be `length` long, refused as `part` where they are not. */
let sized = (bytes, ~part, ~length) =>
  TypedArray.length(bytes) == length ? Ok(bytes) : Error(Length({part, length}))

/** An id, an integer of 0 to 2^32 - 1, as 4 bytes big-endian, refused as `part` outside it. */
let id = (value, ~part) =>
  if Math.floor(value) == value && value >= 0.0 && value <= 4294967295.0 {
    let n = Float.toInt(value)
    Ok(
      Uint8Array.fromArray(
        [24, 16, 8, 0]->Array.map(shift => n->Int.shiftRightUnsigned(shift)->Int.bitwiseAnd(0xff)),
      ),
    )
  } else {
    Error(Range({part: part}))
  }

/** One byte, 0 to 255, refused as `part` outside it. */
let byte = (value, ~part) =>
  value >= 0 && value <= 255 ? Ok(Uint8Array.fromArray([value])) : Error(Range({part: part}))

/** The parts joined in order. */
let join = parts => {
  let joined = Uint8Array.fromLength(
    parts->Array.reduce(0, (total, part) => total + TypedArray.length(part)),
  )
  let _ = parts->Array.reduce(0, (offset, part) => {
    joined->Web.setFrom(part, offset)
    offset + TypedArray.length(part)
  })
  joined
}

let salt = (~master, ~scope) =>
  sized(master, ~part="master", ~length=32)->Result.flatMap(master =>
    id(scope, ~part="scope")->Result.map(scope => derive(Salt, join([master, scope])))
  )

let key = (~master, ~scope) =>
  sized(master, ~part="master", ~length=32)->Result.flatMap(master =>
    id(scope, ~part="scope")->Result.map(scope => derive(Key, join([master, scope])))
  )

let journal = (~key, ~seed) =>
  sized(key, ~part="key", ~length=32)->Result.flatMap(key =>
    sized(seed, ~part="seed", ~length=32)->Result.map(seed => derive(Journal, join([key, seed])))
  )

let parcel = (~key, ~seed) =>
  sized(key, ~part="key", ~length=32)->Result.flatMap(key =>
    sized(seed, ~part="seed", ~length=32)->Result.map(seed => derive(Parcel, join([key, seed])))
  )

let gear = (~salt) =>
  sized(salt, ~part="salt", ~length=32)->Result.map(salt => derive(Gear, salt, ~length=2048))

let score = (~parcel, ~store, ~k) =>
  sized(parcel, ~part="parcel", ~length=32)->Result.flatMap(parcel =>
    id(store, ~part="store")->Result.flatMap(store =>
      byte(k, ~part="k")->Result.map(k => derive(Placement, join([parcel, store, k]), ~length=8))
    )
  )
