/*** An id of 32 bits drawn at random and written as 8 lowercase hex digits, RFC b8f35. */

/** The id written out, as a URL or a message shows it. */
let text = id => id->Float.toString(~radix=16)->String.padStart(8, "0")

let written = /^[0-9a-f]{8}$/

/** The id 8 lowercase hex digits write, none for any other text or for 0, which no id is. */
let ofText = text =>
  written->RegExp.test(text)
    ? Some(Float.parseInt(text, ~radix=16))->Option.filter(id => id > 0.)
    : None

/** The 32 bits of 4 bytes read big-endian, as an id is read from its bytes. */
let ofBytes = (bytes: Uint8Array.t) =>
  [0, 1, 2, 3]->Array.reduce(0., (id, i) =>
    id *. 256. +. bytes->TypedArray.get(i)->Option.mapOr(0., Int.toFloat)
  )

/** How many ids are drawn before a draw gives up, each one a conflict. */
let draws = 16

// Below 2^24 lie the numbered ids, the scaffold's and conform's block, none drawn, RFC b8f35.
let floor = 16777216.

/**
 * An id of a kind drawn by `random` and kept by `kept`, drawn again where it answers it was held
 * already.
 */
let drawn = async (~random, ~kind, kept) => {
  let rec draw = async left =>
    if left == 0 {
      JsError.throwWithMessage(
        `every one of ${Int.toString(draws)} ${kind} ids drawn is held already`,
      )
    } else {
      let id = random()
      // A draw below the floor is drawn again, as a conflict is.
      switch id >= floor && (await kept(id)) {
      | true => id
      | false => await draw(left - 1)
      }
    }
  await draw(draws)
}
