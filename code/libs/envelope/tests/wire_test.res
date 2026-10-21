/***
 * The texts `Wire` writes bytes in: base64url, unpadded, read in that text alone, and a hash's
 * lowercase hex.
 */
open Node

let bytes = Uint8Array.fromArray

test("base64url is written unpadded and read back, for every length of a last group", () =>
  [0, 1, 2, 3, 4, 5, 6]->Array.forEach(length => {
    let given = bytes(Array.fromInitializer(~length, i => 250 - 61 * i &&& 0xff))
    let text = Base64url.encode(given)
    ok(!(text->String.includes("=")), ~message=text)
    deepEqual(Base64url.decode(text), Some(given), ~message=text)
  })
)

test("base64url is its alphabet's", () => {
  deepEqual(Base64url.encode(bytes([0xfb, 0xff])), "-_8")
  deepEqual(Base64url.decode("-_8"), Some(bytes([0xfb, 0xff])))
  deepEqual(Base64url.decode(""), Some(bytes([])))
})

test("base64url in any other text is refused", () =>
  // Padded, base64's own alphabet, a lone digit, and a bit set past the last byte.
  ["AA==", "+/8", "/w", "A", "AB", "AAB", "A A"]->Array.forEach(text =>
    deepEqual(Base64url.decode(text), None, ~message=text)
  )
)

test("hex is lowercase, two digits a byte", () => {
  deepEqual(Hex.encode(bytes([0, 0x0f, 0xa0, 0xff])), "000fa0ff")
  deepEqual(Hex.decode("000fa0ff"), Some(bytes([0, 0x0f, 0xa0, 0xff])))
  ["0F", "0", "0g"]->Array.forEach(text => deepEqual(Hex.decode(text), None, ~message=text))
})
