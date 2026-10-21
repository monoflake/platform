/***
 * What a parcel and a journal seal their segments by, RFC b8f35, written once: the parcel's header,
 * the master's version it holds, and each segment's nonce and associated data.
 */

// What the header takes, what a segment holds but the last, and what its tag adds.
let headed = 41
let segment = 65_536
let tag = 16

/** What a segment but the last takes, sealed with its tag. */
let sealed =
  segment + tag

let magic = [0x4d, 0x4f, 0x46, 0x4c]

/** An integer's low 32 bits, big-endian. */
let u32 = n =>
  [24, 16, 8, 0]->Array.map(shift => n->Int.shiftRightUnsigned(shift)->Int.bitwiseAnd(0xff))

/** The 32-bit integer, big-endian, at `offset`. */
let read32 = (bytes, offset) =>
  [0, 1, 2, 3]->Array.reduce(0., (value, i) =>
    value *. 256. +. bytes->TypedArray.get(offset + i)->Option.getOr(0)->Int.toFloat
  )

/** Whether a master's version is an integer of 1 to 2^32 - 1. */
let versioned = master => Math.floor(master) == master && master >= 1. && master <= 4294967295.

/** The revision, 1, and the master's version: what follows the magic, and begins a journal. */
let begins = (~master) => [1, ...u32(Float.toInt(master))]

/** The header's 41 bytes. */
let header = (~master, ~seed) => {
  let bytes = Uint8Array.fromLength(headed)
  bytes->TypedArray.setArray(Array.concat(magic, begins(~master)))
  bytes->Web.setFrom(seed, 9)
  bytes
}

/** The nonce of segment `i`: 8 zero bytes, then its index. */
let nonce = i => Uint8Array.fromArray(Array.concat(Array.make(~length=8, 0), u32(i)))

/** The associated data of segment `i`: the header, the index, and `final`. */
let associated = (header, i, ~final) => {
  let bytes = Uint8Array.fromLength(headed + 5)
  bytes->Web.setFrom(header, 0)
  bytes->TypedArray.setArrayFrom([...u32(i), final ? 1 : 0], headed)
  bytes
}
