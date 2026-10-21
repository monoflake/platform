/***
 * Bytes as text, RFC 4648's fifth section: base64url, unpadded, and read in that text alone, its
 * unused last bits zero, RFC fhg6w.
 */

let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

let encode = (bytes: Uint8Array.t) => {
  let length = TypedArray.length(bytes)
  let byte = i => i < length ? bytes->TypedArray.get(i)->Option.getOr(0) : 0
  let digit = sextet => alphabet->String.charAt(sextet)
  let text = []
  let at = ref(0)
  while at.contents < length {
    let i = at.contents
    let (b0, b1, b2) = (byte(i), byte(i + 1), byte(i + 2))
    text->Array.push(digit(b0 >> 2))
    text->Array.push(digit(b0 << 4 &&& 0x30 ||| b1 >> 4))
    if i + 1 < length {
      text->Array.push(digit(b1 << 2 &&& 0x3c ||| b2 >> 6))
    }
    if i + 2 < length {
      text->Array.push(digit(b2 &&& 0x3f))
    }
    at := i + 3
  }
  text->Array.join("")
}

/** The bytes the text spells, or none where it is not base64url, unpadded, its unused bits zero. */
let decode = (text: string): option<Uint8Array.t> => {
  let length = String.length(text)
  let sextets = Array.fromInitializer(~length, i =>
    alphabet->String.indexOf(text->String.charAt(i))
  )
  let sextet = i => sextets->Array.get(i)->Option.getOr(0)
  // The bits of the last digit that fall past the last byte, which must be zero.
  let unused = switch Int.mod(length, 4) {
  | 2 => 0x0f
  | 3 => 0x03
  | _ => 0
  }
  if (
    Int.mod(length, 4) == 1 ||
    sextets->Array.some(s => s < 0) ||
    (sextet(length - 1) &&& unused) != 0
  ) {
    None
  } else {
    let bytes = []
    let at = ref(0)
    while at.contents + 1 < length {
      let i = at.contents
      bytes->Array.push((sextet(i) << 2 ||| sextet(i + 1) >> 4) &&& 0xff)
      if i + 2 < length {
        bytes->Array.push((sextet(i + 1) << 4 ||| sextet(i + 2) >> 2) &&& 0xff)
      }
      if i + 3 < length {
        bytes->Array.push((sextet(i + 2) << 6 ||| sextet(i + 3)) &&& 0xff)
      }
      at := i + 4
    }
    Some(Uint8Array.fromArray(bytes))
  }
}
