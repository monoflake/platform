let text = id => id->Float.toString(~radix=16)->String.padStart(8, "0")

let written = /^[0-9a-f]{8}$/

let ofText = text =>
  written->RegExp.test(text)
    ? Some(Float.parseInt(text, ~radix=16))->Option.filter(id => id > 0.)
    : None

let ofBytes = (bytes: Uint8Array.t) =>
  [0, 1, 2, 3]->Array.reduce(0., (id, i) =>
    id *. 256. +. bytes->TypedArray.get(i)->Option.mapOr(0., Int.toFloat)
  )

let taken = (args, ~flag) => {
  let named = `--${flag}`
  switch args->Array.indexOf(named) {
  | -1 => Ok((None, args))
  | at =>
    let given = args->Array.get(at + 1)
    let rest = args->Array.filterWithIndex((_, i) => i != at && i != at + 1)
    switch given->Option.flatMap(ofText) {
    | _ if rest->Array.includes(named) => Error(`${named} is given more than once`)
    | Some(id) => Ok((Some(id), rest))
    | None =>
      switch given {
      | Some(given) => Error(`${named} ${given} is no id, 8 lowercase hex digits`)
      | None => Error(`${named} is given no id, 8 lowercase hex digits`)
      }
    }
  }
}
