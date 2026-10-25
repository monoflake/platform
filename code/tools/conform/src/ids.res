/***
 * An app's id written as 8 lowercase hex digits, RFC b8f35, held as an `int` of the same 32 bits,
 * its top bit the sign.
 */

/** The id's 32 bits read as the number they write, its top bit worth 2^31 and not its sign. */
let toFloat = (id: int) => Int.toFloat(id) +. (id < 0 ? 4294967296. : 0.)

/** The id written out, leading zeros kept. */
let text = id => id->toFloat->Float.toString(~radix=16)->String.padStart(8, "0")

let written = /^[0-9a-f]{8}$/

/** The id 8 lowercase hex digits write, none for any other text or for 0, which no id is. */
let ofText = text =>
  written->RegExp.test(text) && text != "00000000"
    ? Some(Float.parseInt(text, ~radix=16)->Float.toInt)
    : None

/** `--app <id>` taken out of the arguments, the id and what is left, or why not. */
let app = args =>
  switch args->Array.indexOf("--app") {
  | -1 => Error("--app names no app, the 8 hex digits of hello's id")
  | at =>
    let rest = args->Array.filterWithIndex((_, i) => i != at && i != at + 1)
    switch args->Array.get(at + 1)->Option.flatMap(ofText) {
    | Some(id) => Ok((id, rest))
    | None =>
      Error(
        `--app ${args->Array.get(at + 1)->Option.getOr("")} is no app's id, 8 lowercase hex digits`,
      )
    }
  }
