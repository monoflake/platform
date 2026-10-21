/*** A content's hash as text: its bytes in lowercase hex digits, as b8f35 writes it. */

let digits = "0123456789abcdef"

let encode = (bytes: Uint8Array.t) =>
  Array.fromInitializer(~length=TypedArray.length(bytes), i => {
    let byte = bytes->TypedArray.get(i)->Option.getOr(0)
    digits->String.charAt(byte >> 4) ++ digits->String.charAt(byte &&& 0x0f)
  })->Array.join("")

/** The bytes the text spells, or none where it is not lowercase hex digits, two a byte. */
let decode = (text: string): option<Uint8Array.t> => {
  let length = String.length(text)
  let nibbles = Array.fromInitializer(~length, i => digits->String.indexOf(text->String.charAt(i)))
  if Int.mod(length, 2) == 1 || nibbles->Array.some(n => n < 0) {
    None
  } else {
    let nibble = i => nibbles->Array.get(i)->Option.getOr(0)
    Some(
      Uint8Array.fromArray(
        Array.fromInitializer(~length=length / 2, i => nibble(2 * i) << 4 ||| nibble(2 * i + 1)),
      ),
    )
  }
}
