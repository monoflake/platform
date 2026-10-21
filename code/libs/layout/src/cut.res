/***
 * Content cut by FastCDC with normalized chunking at level 2, RFC b8f35, its 64-bit hash held as
 * two 32-bit halves so no float ever carries it.
 */

let least = 262_144
let normal = 1_048_576
let most = 4_194_304

// The 22-bit mask below `normal` and the 18-bit one from it, each as its high and low halves.
let smallHigh = 0xd937
let smallLow = 0x67537000
let largeHigh = 0xd907
let largeLow = 0x07537000

type t = {
  // The gear table's 256 words, each as its high and low halves.
  gearHigh: array<int>,
  gearLow: array<int>,
  mutable high: int,
  mutable low: int,
  // The offset in the piece of the next byte, so the length the piece holds so far.
  mutable at: int,
}

type refused = Gear

/** The 32-bit word, little-endian, at `offset`. */
let word = (bytes, offset) =>
  [0, 1, 2, 3]->Array.reduce(0, (word, i) =>
    word->Int.bitwiseOr(bytes->TypedArray.get(offset + i)->Option.getOr(0)->Int.shiftLeft(8 * i))
  )

let make = (~gear) =>
  TypedArray.length(gear) == 2048
    ? Ok({
        gearHigh: Array.fromInitializer(~length=256, b => word(gear, 8 * b + 4)),
        gearLow: Array.fromInitializer(~length=256, b => word(gear, 8 * b)),
        high: 0,
        low: 0,
        at: 0,
      })
    : Error(Gear)

let push = (t, part) => {
  let pieces = []
  let length = TypedArray.length(part)
  let k = ref(0)
  let high = ref(t.high)
  let low = ref(t.low)
  let at = ref(t.at)
  while k.contents < length {
    if at.contents < least {
      // Bytes below `least` are taken whole and never hashed.
      let taken = Math.Int.min(least - at.contents, length - k.contents)
      at := at.contents + taken
      k := k.contents + taken
    } else {
      let byte = part->TypedArray.get(k.contents)->Option.getOr(0)
      let ends = if at.contents == most - 1 {
        true
      } else {
        let gearHigh = t.gearHigh->Array.getUnsafe(byte)
        let gearLow = t.gearLow->Array.getUnsafe(byte)
        // (hash << 1) + gear[byte], wrapping at 64 bits: the low half's carry goes into the high.
        let shifted = low.contents->Int.shiftLeft(1)
        let sum = shifted + gearLow
        let carry =
          shifted
          ->Int.bitwiseAnd(gearLow)
          ->Int.bitwiseOr(shifted->Int.bitwiseOr(gearLow)->Int.bitwiseAnd(Int.bitwiseNot(sum)))
          ->Int.shiftRightUnsigned(31)
        high :=
          high.contents
          ->Int.shiftLeft(1)
          ->Int.bitwiseOr(low.contents->Int.shiftRightUnsigned(31)) +
          gearHigh +
          carry
        low := sum
        let (maskHigh, maskLow) =
          at.contents < normal ? (smallHigh, smallLow) : (largeHigh, largeLow)
        high.contents->Int.bitwiseAnd(maskHigh) == 0 && low.contents->Int.bitwiseAnd(maskLow) == 0
      }
      at := at.contents + 1
      k := k.contents + 1
      if ends {
        pieces->Array.push(at.contents)
        high := 0
        low := 0
        at := 0
      }
    }
  }
  t.high = high.contents
  t.low = low.contents
  t.at = at.contents
  pieces
}

let finish = t =>
  if t.at > 0 {
    let length = t.at
    t.high = 0
    t.low = 0
    t.at = 0
    Some(length)
  } else {
    None
  }
